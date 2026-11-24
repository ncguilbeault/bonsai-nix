#!/usr/bin/env bash
# new-release.sh
#
# Usage:
#   bash scripts/new-release.sh [--write] [--bonsai <version>] [--wine <version>] [--nvidia-libs <version>] [--nvcuda head|bundled|<rev>] [--cuda-major <n>] [--python <version>|<major>[.<minor>]] [--hold-wine] [--hold-nvidia-libs] [--hold-nvcuda] [--hold-cuda] [--hold-python]
#
# Builds the release set for a new Bonsai version. Versions come from scripts/latest-versions.sh and hashes from scripts/fetch-hashes.sh. The output lists the sources (version, URL and hash of each), then the bindings and the release set to add to nix/releases.nix, then any notes.
#
# Every dependency defaults to its latest upstream version:
#   bonsai, wine, nvidia-libs  latest release
#   nvcuda                     head of the default branch, built from source with an empty patch list, since patches are tied to the revision they were written for
#   cuda                       latest NVIDIA manifests of the newest CUDA major version, with hashes taken from the manifests
#   python                     newest release with a Windows installer
#   wine patches               a new Wine version takes the patches of the highest release set's Wine
#
# Options:
#   --write                    add the bindings and the release set to nix/releases.nix instead of only printing them
#   --bonsai <version>         Bonsai version of the new release set
#   --wine <version>           Wine version
#   --nvidia-libs <version>    nvidia-libs version
#   --nvcuda head|bundled|<rev>
#                              nvcuda revision; "bundled" leaves nvcuda out of the release set, so the nvcuda.dll shipped with nvidia-libs is used
#   --cuda-major <n>           CUDA major version to take the latest manifests of
#   --python <version>|<major>[.<minor>]
#                              Python version, or a major version (3) or series (3.13) to take the newest release of
#   --hold-wine, --hold-nvidia-libs, --hold-nvcuda, --hold-cuda, --hold-python
#                              keep that dependency as it is in the highest release set, including its patches
#
# A dependency whose version matches the highest release set reuses that set's binding. Otherwise a binding named after the version is reused if nix/releases.nix has one and added if not. The hash of a reused binding is checked against the fetched one and corrected when it differs.
#
# The script edits nix/releases.nix as text and relies on its layout: bindings indented by two spaces in a let block closed by a line holding only "in", and release sets of the form '  "<version>" = {' ... '  };' in an attribute set closed by the last "}" line.
#
# Prerequisites: nix, curl, git

set -euo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
releases_file="$scripts/../nix/releases.nix"

write=0
bonsai=
wine=
nvidia_libs=
python=
nvcuda=head
cuda_major=latest
hold_wine=0
hold_nvidia_libs=0
hold_cuda=0
hold_python=0
while [ $# -gt 0 ]; do
  case $1 in
    --write) write=1; shift ;;
    --bonsai) bonsai=$2; shift 2 ;;
    --wine) wine=$2; shift 2 ;;
    --nvidia-libs) nvidia_libs=$2; shift 2 ;;
    --python) python=$2; shift 2 ;;
    --nvcuda) nvcuda=$2; shift 2 ;;
    --cuda-major) cuda_major=$2; shift 2 ;;
    --hold-wine) hold_wine=1; shift ;;
    --hold-nvidia-libs) hold_nvidia_libs=1; shift ;;
    --hold-nvcuda) nvcuda=keep; shift ;;
    --hold-cuda) hold_cuda=1; shift ;;
    --hold-python) hold_python=1; shift ;;
    *) echo "Error: unknown argument $1" >&2; exit 1 ;;
  esac
done

nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Looking up latest versions..." >&2
# A --python value of one or two components is a major version or series to roll forward within.
python_scope=()
if [[ $python =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  python_scope=(--python-series "$python")
  python=
fi
latest=$(bash "$scripts/latest-versions.sh" --plain --cuda-major "$cuda_major" ${python_scope[@]+"${python_scope[@]}"})
get() { sed -n "s/^$1 //p" <<<"$latest"; }

prev=$(get pinned.release)
bonsai=${bonsai:-$(get bonsai)}
if [ "$hold_wine" = 1 ]; then wine=$(get pinned.wine); fi
if [ "$hold_nvidia_libs" = 1 ]; then nvidia_libs=$(get pinned.nvidiaLibs); fi
if [ "$hold_python" = 1 ]; then python=$(get pinned.python); fi
wine=${wine:-$(get wine)}
nvidia_libs=${nvidia_libs:-$(get nvidiaLibs)}
python=${python:-$(get python)}
case $nvcuda in
  keep) nvcuda_rev=$(get pinned.nvcuda) ;;
  head) nvcuda_rev=$(get nvcudaHead) ;;
  bundled) nvcuda_rev=bundled ;;
  *) nvcuda_rev=$nvcuda ;;
esac
if [ -z "$nvcuda_rev" ]; then
  echo "Error: no nvcuda revision found for --nvcuda $nvcuda" >&2
  exit 1
fi

if grep -q "^  \"$bonsai\" = {\$" "$releases_file"; then
  echo "Error: Bonsai $bonsai is already listed in nix/releases.nix; pass --bonsai <version> for another release." >&2
  exit 1
fi

# The highest release set as written in the file, used to carry its bindings and patches forward.
prev_block=$(awk -v h="  \"$prev\" = {" '$0 == h { p = 1 } p { print } p && $0 == "  };" { exit }' "$releases_file")
prev_ref() { sed -n "s/^    $1 = \(.*\);\$/\1/p" <<<"$prev_block" | head -n 1; }

ident() { sed 's/[^A-Za-z0-9]/_/g' <<<"$1"; }
has_binding() { grep -q "^  $1 = {\$" "$releases_file"; }

# Sets $ref to the expression a release set uses for a dependency and $emit to 1 when a new binding has to be added for it.
choose() {
  local key=$1 new=$2 pinned=$3 name=$4 line
  line=$(prev_ref "$key")
  emit=0
  if [ "$new" = "$pinned" ] && [ -n "$line" ]; then
    ref=$line
  else
    ref=$name
    if ! has_binding "$name"; then emit=1; fi
  fi
}

bindings="$work/bindings.nix"
entry="$work/entry.nix"
candidate="$work/releases.nix"
notes="$work/notes"
: >"$bindings"
: >"$notes"

choose nvidiaLibs "$nvidia_libs" "$(get pinned.nvidiaLibs)" "nvidiaLibs_$(ident "$nvidia_libs")"
nvidia_libs_ref=$ref
if [ "$emit" = 1 ]; then
  cat >>"$bindings" <<EOF

  $ref = {
    version = "$nvidia_libs";
    sha256 = "@nvidiaLibs.sha256@";
  };
EOF
fi

# The release set has no nvcuda line when the nvcuda.dll bundled with nvidia-libs is used.
nvcuda_line=
emit=0
if [ "$nvcuda_rev" = "bundled" ]; then
  echo "nvcuda is left out of the release set; the nvcuda.dll bundled with nvidia-libs $nvidia_libs is used ($(get nvcudaBundled | cut -c1-12), unpatched)." >>"$notes"
else
  choose nvcuda "$nvcuda_rev" "$(get pinned.nvcuda)" "nvcuda_${nvcuda_rev:0:7}"
  nvcuda_line="    nvcuda = $ref;"
fi
if [ "$emit" = 1 ]; then
  cat >>"$bindings" <<EOF

  $ref = {
    rev = "$nvcuda_rev";
    sha256 = "@nvcuda.sha256@";
    patches = [ ];
  };
EOF
  echo "nvcuda moves to revision ${nvcuda_rev:0:12} with no patches; add any that are still needed to $ref." >>"$notes"
fi

components=$(get component)
cuda_changed=0
while read -r name pinned_path latest_path hash; do
  if [ "$hold_cuda" = 1 ]; then
    continue
  elif [ "$latest_path" = "missing" ]; then
    echo "CUDA component $name is not in the latest manifest and is left out of the new component set." >>"$notes"
    cuda_changed=1
  elif [ "$pinned_path" != "$latest_path" ]; then
    cuda_changed=1
  fi
done <<<"$components"

if [ "$cuda_changed" = 0 ]; then
  cuda_label=$(get pinned.cudaRedist)
  choose cudaRedist "$cuda_label" "$cuda_label" "cudaRedist_$(ident "$cuda_label")"
else
  cuda_minor=$(cut -d. -f1,2 <<<"$(get cuda)")
  cuda_label="$cuda_minor-cudnn$(get cudnn)"
  cuda_name="cudaRedist_$(ident "$cuda_minor")"
  if has_binding "$cuda_name"; then
    cuda_label="$(get cuda)-cudnn$(get cudnn)"
    cuda_name="cudaRedist_$(ident "$cuda_label")"
  fi
  choose cudaRedist "$cuda_label" "" "$cuda_name"
fi
cuda_ref=$ref
if [ "$emit" = 1 ]; then
  {
    printf '\n  %s = {\n    version = "%s";\n    components = [\n' "$ref" "$cuda_label"
    while read -r name pinned_path latest_path hash; do
      [ "$latest_path" != "missing" ] || continue
      printf '      {\n        name = "%s";\n        path = "%s";\n        sha256 = "%s";\n      }\n' "$name" "$latest_path" "$hash"
    done <<<"$components"
    printf '    ];\n  };\n'
  } >>"$bindings"
fi

choose python "$python" "$(get pinned.python)" "python_$(ident "$python")"
python_ref=$ref
if [ "$emit" = 1 ]; then
  cat >>"$bindings" <<EOF

  $ref = {
    version = "$python";
    sha256 = "@python.sha256@";
  };
EOF
fi

choose wine "$wine" "$(get pinned.wine)" "wine_$(ident "$wine")"
wine_ref=$ref
if [ "$emit" = 1 ]; then
  # Patches are carried over from the Wine binding of the highest release set.
  wine_patches=$(awk -v h="  $(prev_ref wine) = {" '$0 == h { p = 1 } p { print } p && $0 == "  };" { exit }' "$releases_file" \
    | sed -n 's/^    patches = \(.*\);$/\1/p' | head -n 1)
  cat >>"$bindings" <<EOF

  $ref = {
    version = "$wine";
    sha256 = "@wine.sha256@";
    stagingSha256 = "@wine.stagingSha256@";
    patches = ${wine_patches:-[ ]};
  };
EOF
fi

cat >"$entry" <<EOF

  "$bonsai" = {
    bonsai.sha256 = "@bonsai.sha256@";
    wine = $wine_ref;
    nvidiaLibs = $nvidia_libs_ref;${nvcuda_line:+
$nvcuda_line}
    cudaRedist = $cuda_ref;
    python = $python_ref;
  };
EOF

# The candidate file: the bindings go before the "in" line, the release set before the closing brace.
awk -v bindings="$bindings" -v entry="$entry" '
  function emit(file,   line) { while ((getline line < file) > 0) print line }
  { lines[NR] = $0 }
  $0 == "in" && !in_line { in_line = NR }
  $0 == "}" { last = NR }
  END {
    if (!in_line || !last || last < in_line) exit 1
    for (i = 1; i <= NR; i++) {
      if (i == in_line) emit(bindings)
      if (i == last) emit(entry)
      print lines[i]
    }
  }
' "$releases_file" >"$candidate" || {
  echo "Error: nix/releases.nix does not have the expected layout." >&2
  exit 1
}

# Replaces every occurrence of a literal string in a file.
replace_literal() {
  awk -v old="$2" -v new="$3" '
    {
      out = ""
      while ((i = index($0, old)) > 0) {
        out = out substr($0, 1, i - 1) new
        $0 = substr($0, i + length(old))
      }
      print out $0
    }
  ' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# Hashes of the new release set as the candidate file has them, one "<field> <hash>" line each.
current=$(RELEASE=$bonsai nix eval --impure --raw --file "$candidate" --apply '
  releases:
  let r = releases.${builtins.getEnv "RELEASE"};
  in
  "bonsai.sha256 ${r.bonsai.sha256}\n"
  + "wine.sha256 ${r.wine.sha256}\n"
  + "wine.stagingSha256 ${r.wine.stagingSha256}\n"
  + "nvidiaLibs.sha256 ${r.nvidiaLibs.sha256}\n"
  + "nvcuda.sha256 ${r.nvcuda.sha256 or ""}\n"
  + "python.sha256 ${r.python.sha256}\n"
')

echo "Fetching sources..." >&2
sources=$(bash "$scripts/fetch-hashes.sh" --file "$candidate" --release "$bonsai" --no-cuda)

for field in bonsai.sha256 wine.sha256 wine.stagingSha256 nvidiaLibs.sha256 nvcuda.sha256 python.sha256; do
  if [ "$field" = "nvcuda.sha256" ] && [ -z "$nvcuda_line" ]; then continue; fi
  fetched=$(sed -n "s/^  $field = \"\([^\"]*\)\";.*/\1/p" <<<"$sources")
  if [ -z "$fetched" ]; then
    echo "Error: no hash fetched for $field" >&2
    exit 1
  fi
  if grep -qF "@$field@" "$candidate"; then
    for file in "$bindings" "$entry" "$candidate"; do
      replace_literal "$file" "@$field@" "$fetched"
    done
    continue
  fi
  existing=$(sed -n "s/^$field //p" <<<"$current")
  if [ "$existing" != "$fetched" ]; then
    if [ "$(grep -cF "\"$existing\"" "$candidate")" = 1 ]; then
      replace_literal "$candidate" "\"$existing\"" "\"$fetched\""
      echo "$field of the existing binding was \"$existing\"; the fetched hash is \"$fetched\"$([ "$write" = 1 ] && echo " and has been written" || echo ", which --write corrects")." >>"$notes"
    else
      echo "$field of the existing binding is \"$existing\" but the fetched hash is \"$fetched\"; correct it by hand." >>"$notes"
    fi
  fi
done

if grep -q '@[A-Za-z.]*sha256@' "$candidate" || ! nix eval --file "$candidate" --apply builtins.attrNames >/dev/null; then
  echo "Error: the generated release set does not evaluate." >&2
  exit 1
fi

printf 'Sources for Bonsai %s\n' "$bonsai"
sed 1d <<<"$sources"
while read -r name pinned_path latest_path hash; do
  if [ "$cuda_changed" = 1 ] && [ "$latest_path" != "missing" ]; then
    printf '  cudaRedist.components.%s.sha256 = "%s";  # %s https://developer.download.nvidia.com/compute/%s\n' "$name" "$hash" "$cuda_label" "$latest_path"
  fi
done <<<"$components"
if [ "$cuda_changed" = 0 ]; then
  printf '  cudaRedist = %s;  # %s, unchanged\n' "$cuda_ref" "$cuda_label"
fi

if [ -s "$bindings" ]; then
  printf '\nBindings for the let block of nix/releases.nix\n'
  cat "$bindings"
fi
printf '\nRelease set for nix/releases.nix\n'
cat "$entry"

if [ -s "$notes" ]; then
  printf '\nNotes\n'
  sed 's/^/  /' "$notes"
fi

if [ "$write" = 1 ]; then
  cp "$candidate" "$releases_file"
  printf '\nAdded Bonsai %s to nix/releases.nix.\n' "$bonsai"
else
  printf '\nNothing was written. Run with --write to add this to nix/releases.nix.\n'
fi
