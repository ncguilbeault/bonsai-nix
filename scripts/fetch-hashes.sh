#!/usr/bin/env bash
# fetch-hashes.sh
#
# Usage:
#   bash scripts/fetch-hashes.sh [--file <path>] [--release <version>] [--no-cuda]
#
# Prints the sha256 hash of every source pinned in nix/releases.nix. Versions, revisions and archive paths are read from the release sets and each source is downloaded to compute its hash; a source shared by several release sets is downloaded once.
#
# Each release set is printed as a block with one line per source, named after the field the hash belongs to (bonsai.sha256, wine.sha256, wine.stagingSha256, nvidiaLibs.sha256, nvcuda.sha256, python.sha256, cudaRedist.components.<name>.sha256) and followed by a comment giving the version or revision and the URL or flake reference it was fetched from.
#
# Options:
#   --file <path>        read release sets from this file instead of nix/releases.nix
#   --release <version>  print only the release set of this Bonsai version
#   --no-cuda            skip the CUDA component archives
#
# Prerequisites: nix

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

releases_file="$repo_root/nix/releases.nix"
only_release=
with_cuda=1
while [ $# -gt 0 ]; do
  case $1 in
    --file) releases_file=$2; shift 2 ;;
    --release) only_release=$2; shift 2 ;;
    --no-cuda) with_cuda=0; shift ;;
    *) echo "Error: unknown argument $1" >&2; exit 1 ;;
  esac
done

if ! command -v nix &>/dev/null; then
  echo "Error: nix is not installed." >&2
  echo "Please install Nix from https://nixos.org/download.html" >&2
  exit 1
fi

nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

json_hash() { sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'; }

# One "release <bonsai version>" line per release set, each followed by one "<file|flake> <releases.nix field> <label> <url or flake reference>" line per source.
sources=$(nix eval --raw --file "$releases_file" --apply '
  releases:
  let
    inherit (builtins) attrNames concatMap concatStringsSep elemAt sort splitVersion compareVersions;
    # Wine tarballs for X.0 releases live under X.0/, later ones under X.x/.
    wineDir = v:
      let parts = splitVersion v;
      in "${elemAt parts 0}.${if elemAt parts 1 == "0" then "0" else "x"}";
    versions = sort (a: b: compareVersions a b < 0) (attrNames releases);
    linesFor = v:
      let r = releases.${v};
      in
      [
        "release ${v}"
        "file bonsai.sha256 ${v} https://github.com/bonsai-rx/bonsai/releases/download/${v}/Bonsai-${v}.exe"
        "file wine.sha256 ${r.wine.version} https://dl.winehq.org/wine/source/${wineDir r.wine.version}/wine-${r.wine.version}.tar.xz"
      ]
      ++ (if (r.wine.stagingSha256 or null) != null
          then [ "flake wine.stagingSha256 ${r.wine.version} github:wine-staging/wine-staging/v${r.wine.version}" ]
          else [ ])
      ++ [
        "file nvidiaLibs.sha256 ${r.nvidiaLibs.version} https://github.com/SveSop/nvidia-libs/releases/download/v${r.nvidiaLibs.version}/nvidia-libs-v${r.nvidiaLibs.version}.tar.xz"
      ]
      ++ (if r ? nvcuda
          then [ "flake nvcuda.sha256 ${r.nvcuda.rev} github:SveSop/nvcuda/${r.nvcuda.rev}" ]
          else [ ])
      ++ [
        "file python.sha256 ${r.python.version} https://www.python.org/ftp/python/${r.python.version}/python-${r.python.version}-amd64.exe"
      ]
      ++ map (c: "file cudaRedist.components.${c.name}.sha256 ${r.cudaRedist.version} https://developer.download.nvidia.com/compute/${c.path}") r.cudaRedist.components;
  in
  concatStringsSep "\n" (concatMap linesFor versions)
')

if [ -n "$only_release" ]; then
  sources=$(awk -v r="$only_release" '$1 == "release" { p = ($2 == r) } p' <<<"$sources")
fi
if [ "$with_cuda" = 0 ]; then
  sources=$(grep -v '^[a-z]* cudaRedist\.' <<<"$sources" || true)
fi

# Hashes already fetched in this run, as parallel arrays indexed together.
fetched_refs=()
fetched_hashes=()

# Sets $hash to the hash of a source, fetching it unless it was fetched earlier in the run.
fetch() {
  local kind=$1 ref=$2 i
  for i in "${!fetched_refs[@]}"; do
    if [ "${fetched_refs[$i]}" = "$ref" ]; then
      hash=${fetched_hashes[$i]}
      return
    fi
  done
  case $kind in
    file) hash=$(nix store prefetch-file --json "$ref" </dev/null | json_hash) ;;
    flake) hash=$(nix flake prefetch --json "$ref" </dev/null | json_hash) ;;
  esac
  if [ -z "$hash" ]; then
    echo "Error: no hash obtained for $ref" >&2
    exit 1
  fi
  fetched_refs+=("$ref")
  fetched_hashes+=("$hash")
}

while read -r kind field label ref; do
  if [ "$kind" = "release" ]; then
    printf 'Bonsai %s\n' "$field"
    continue
  fi
  fetch "$kind" "$ref"
  printf '  %s = "%s";  # %s %s\n' "$field" "$hash" "$label" "$ref"
done <<<"$sources"
