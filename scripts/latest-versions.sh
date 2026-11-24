#!/usr/bin/env bash
# latest-versions.sh
#
# Usage:
#   bash scripts/latest-versions.sh [--plain] [--cuda-major <n>|latest] [--python-series <major>[.<minor>]]
#
# Prints the latest upstream version of every dependency next to its pin in the highest release set of nix/releases.nix, marking with "*" the ones that are ahead of the pin. When a CUDA component is ahead, a components list for nix/releases.nix follows, with paths and hashes taken from NVIDIA's manifests.
#
# Sources:
#   bonsai, nvidia-libs  latest GitHub release
#   wine                 highest wine-staging tag of the form vX.Y, since a release set needs both the Wine tarball and the matching wine-staging tree
#   nvcuda               head of the default branch, and the revision bundled as a submodule by the latest nvidia-libs release; the pin reads "bundled" for a release set without nvcuda
#   python               per series, the highest patch release with a Windows amd64 installer on python.org; the latest version is that of the newest series
#   cuda, cudnn          NVIDIA's redist manifests: the latest CUDA manifest of one major version and the latest cuDNN manifest
#
# Options:
#   --plain                           print one "<key> <value>" line per pin and per latest version instead of the table, for use by other scripts
#   --cuda-major <n>|latest           CUDA major version to take the latest manifest of; "latest" is the newest major. Defaults to the pinned major.
#   --python-series <major>[.<minor>] look only at this Python major version (3) or series (3.13). Defaults to the pinned series and every newer one.
#
# Prerequisites: nix, curl, git

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

plain=0
cuda_major=
python_scope=
while [ $# -gt 0 ]; do
  case $1 in
    --plain) plain=1; shift ;;
    --cuda-major) cuda_major=$2; shift 2 ;;
    --python-series) python_scope=$2; shift 2 ;;
    *) echo "Error: unknown argument $1" >&2; exit 1 ;;
  esac
done

for tool in nix curl git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Error: $tool is not installed." >&2
    exit 1
  fi
done

nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

nvidia_mirror=https://developer.download.nvidia.com/compute

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# One "<key> <value>" line per pin of the highest release set.
pins=$(nix eval --raw --file "$repo_root/nix/releases.nix" --apply '
  releases:
  let
    inherit (builtins) attrNames compareVersions elemAt head length match sort;
    versions = sort (a: b: compareVersions a b < 0) (attrNames releases);
    latest = elemAt versions (length versions - 1);
    r = releases.${latest};
  in
  "bonsai ${latest}\n"
  + "wine ${r.wine.version}\n"
  + "nvidiaLibs ${r.nvidiaLibs.version}\n"
  + "nvcuda ${r.nvcuda.rev or "bundled"}\n"
  + "python ${r.python.version}\n"
  + "cudaRedist ${r.cudaRedist.version}\n"
  + "cudaMajor ${head (match "([0-9]+).*" r.cudaRedist.version)}\n"
')

pin() { sed -n "s/^$1 //p" <<<"$pins"; }

# Tag of the latest GitHub release of a repository, read from the redirect of its releases/latest page.
github_latest() {
  local url
  url=$(curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/$1/releases/latest")
  echo "${url##*/tag/}"
}

# Highest version among the redistrib_<version>.json manifests of an NVIDIA redist directory, optionally restricted to one major version.
latest_manifest() {
  curl -fsSL "$nvidia_mirror/$1/" \
    | grep -o "redistrib_${2:-[0-9]*}\.[0-9.]*\.json" \
    | sed 's/^redistrib_//; s/\.json$//' \
    | sort -Vu | tail -n 1
}

rows=()
row() {
  local mark=" "
  if [ "$2" != "$3" ]; then mark="*"; fi
  rows+=("$(printf '%s %-14s %-18s %s' "$mark" "$1" "$2" "$3")")
}

bonsai_pin=$(pin bonsai)
bonsai_latest=$(github_latest bonsai-rx/bonsai)
row bonsai "$bonsai_pin" "$bonsai_latest"

wine_latest=$(git ls-remote --tags --refs https://github.com/wine-staging/wine-staging \
  | sed -n 's|.*refs/tags/v\([0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' | sort -V | tail -n 1)
row wine "$(pin wine)" "$wine_latest"

nvidia_libs_tag=$(github_latest SveSop/nvidia-libs)
row nvidia-libs "$(pin nvidiaLibs)" "${nvidia_libs_tag#v}"

nvcuda_pin=$(pin nvcuda)
nvcuda_head=$(git ls-remote https://github.com/SveSop/nvcuda HEAD | cut -f1)
# The submodule revision is only available from the GitHub API, which is rate limited for anonymous clients.
nvcuda_bundled=$(curl -fsSL "https://api.github.com/repos/SveSop/nvidia-libs/contents/nvcuda?ref=$nvidia_libs_tag" 2>/dev/null \
  | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -n 1 || true)
# A release set without an nvcuda pin uses the one bundled with nvidia-libs, so neither revision counts as a difference.
if [ "$nvcuda_pin" = "bundled" ]; then
  rows+=("$(printf '  %-14s %-18s %s' nvcuda "bundled" "${nvcuda_head:0:12} (branch head)")")
  rows+=("$(printf '  %-14s %-18s %s' "" "bundled" "${nvcuda_bundled:0:12} (bundled by nvidia-libs $nvidia_libs_tag)")")
else
  row nvcuda "${nvcuda_pin:0:12}" "${nvcuda_head:0:12} (branch head)"
  row "" "${nvcuda_pin:0:12}" "${nvcuda_bundled:0:12} (bundled by nvidia-libs $nvidia_libs_tag)"
fi

python_pin=$(pin python)
python_series_pin=$(cut -d. -f1,2 <<<"$python_pin")
python_latest=
python_versions=$(curl -fsSL https://www.python.org/ftp/python/ \
  | sed -n 's|.*href="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)/".*|\1|p' | sort -Vu)
for series in $(cut -d. -f1,2 <<<"$python_versions" | sort -Vu); do
  if [ -n "$python_scope" ]; then
    case $series in
      "$python_scope" | "$python_scope".*) ;;
      *) continue ;;
    esac
  elif [ "$(printf '%s\n' "$python_series_pin" "$series" | sort -V | head -n 1)" != "$python_series_pin" ]; then
    continue
  fi
  found="none with a Windows installer"
  for v in $(grep "^${series/./\\.}\." <<<"$python_versions" | sort -Vr); do
    if curl -fsIL -o /dev/null "https://www.python.org/ftp/python/$v/python-$v-amd64.exe"; then
      found=$v
      python_latest=$v
      break
    fi
  done
  if [ "$series" = "$python_series_pin" ]; then
    row "python $series" "$python_pin" "$found"
  else
    mark=" "
    if [ "$found" = "$python_latest" ]; then mark="*"; fi
    rows+=("$(printf '%s %-14s %-18s %s' "$mark" "python $series" "" "$found")")
  fi
done

if [ -z "$python_latest" ]; then
  echo "Error: no Python ${python_scope:-$python_series_pin or newer} release with a Windows installer found." >&2
  exit 1
fi

cuda_newest=$(latest_manifest cuda/redist)
if [ "$cuda_major" = "latest" ]; then cuda_major=${cuda_newest%%.*}; fi
cuda_major=${cuda_major:-$(pin cudaMajor)}
cuda_latest=$(latest_manifest cuda/redist "$cuda_major")
if [ -z "$cuda_latest" ]; then
  echo "Error: no CUDA $cuda_major manifest found." >&2
  exit 1
fi
cudnn_latest=$(latest_manifest cudnn/redist)
curl -fsSL -o "$work/cuda.json" "$nvidia_mirror/cuda/redist/redistrib_$cuda_latest.json"
curl -fsSL -o "$work/cudnn.json" "$nvidia_mirror/cudnn/redist/redistrib_$cudnn_latest.json"

# One "<name> <pinned path> <latest path> <latest hash>" line per pinned CUDA component.
components=$(MANIFESTS=$work CUDA_MAJOR=$cuda_major nix eval --impure --raw --file "$repo_root/nix/releases.nix" --apply '
  releases:
  let
    inherit (builtins) attrNames compareVersions concatStringsSep convertHash elemAt fromJSON getEnv length readFile sort substring stringLength;
    versions = sort (a: b: compareVersions a b < 0) (attrNames releases);
    r = releases.${elemAt versions (length versions - 1)};
    dir = getEnv "MANIFESTS";
    manifests = {
      "cuda/redist/" = fromJSON (readFile "${dir}/cuda.json");
      "cudnn/redist/" = fromJSON (readFile "${dir}/cudnn.json");
    };
    hasPrefix = p: s: substring 0 (stringLength p) s == p;
    lineFor = c:
      let
        prefix = if hasPrefix "cudnn/redist/" c.path then "cudnn/redist/" else "cuda/redist/";
        platform = (manifests.${prefix}.${c.name} or { })."windows-x86_64" or null;
        # cuDNN archives are split by the CUDA major version they are built against.
        entry =
          if platform == null then null
          else if platform ? relative_path then platform
          else platform."cuda${getEnv "CUDA_MAJOR"}" or null;
      in
      if entry == null then "${c.name} ${c.path} missing -"
      else "${c.name} ${c.path} ${prefix}${entry.relative_path} ${convertHash { hash = entry.sha256; hashAlgo = "sha256"; toHashFormat = "sri"; }}";
  in
  concatStringsSep "\n" (map lineFor r.cudaRedist.components)
')

# The archive version sits between the platform and the "-archive" suffix of the file name.
archive_version() { sed 's/.*-windows-x86_64-//; s/-archive\.zip$//' <<<"$1"; }

cuda_changed=0
while read -r name pinned latest hash; do
  if [ "$latest" = "missing" ]; then
    row "$name" "$(archive_version "$pinned")" "not in the manifest"
  else
    row "$name" "$(archive_version "$pinned")" "$(archive_version "$latest")"
  fi
  if [ "$pinned" != "$latest" ]; then cuda_changed=1; fi
done <<<"$components"

if [ "$plain" = 1 ]; then
  printf 'pinned.release %s\n' "$bonsai_pin"
  printf 'pinned.wine %s\n' "$(pin wine)"
  printf 'pinned.nvidiaLibs %s\n' "$(pin nvidiaLibs)"
  printf 'pinned.nvcuda %s\n' "$nvcuda_pin"
  printf 'pinned.python %s\n' "$python_pin"
  printf 'pinned.cudaRedist %s\n' "$(pin cudaRedist)"
  printf 'bonsai %s\n' "$bonsai_latest"
  printf 'wine %s\n' "$wine_latest"
  printf 'nvidiaLibs %s\n' "${nvidia_libs_tag#v}"
  printf 'nvcudaHead %s\n' "$nvcuda_head"
  printf 'nvcudaBundled %s\n' "$nvcuda_bundled"
  printf 'python %s\n' "$python_latest"
  printf 'cuda %s\n' "$cuda_latest"
  printf 'cudnn %s\n' "$cudnn_latest"
  # component <name> <pinned path> <latest path> <latest hash>
  sed 's/^/component /' <<<"$components"
  exit 0
fi

printf '  %-14s %-18s %s\n' "" "pinned ($bonsai_pin)" "latest"
printf '%s\n' "${rows[@]}"
printf '\nCUDA manifest %s (latest %s.x; newest overall %s), cuDNN manifest %s\n' "$cuda_latest" "$cuda_major" "$cuda_newest" "$cudnn_latest"

if [ "$cuda_changed" = 1 ]; then
  printf '\ncomponents = [\n'
  while read -r name pinned latest hash; do
    [ "$latest" != "missing" ] || continue
    printf '  {\n    name = "%s";\n    path = "%s";\n    sha256 = "%s";\n  }\n' "$name" "$latest" "$hash"
  done <<<"$components"
  printf '];\n'
fi
