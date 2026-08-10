#!/usr/bin/env bash
# fetch-hashes.sh
#
# Usage:
#   bash scripts/fetch-hashes.sh
#
# Prints the sha256 hashes needed by flake.nix (bonsaiSha256, wineSha256,
# wineStagingSha256, nvidiaLibsSha256), reading the versions from flake.nix itself,
# followed by the per-component hashes for nix/cuda-redist.nix, reading the archive
# paths from that file.
#
# Prerequisites: nix

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flake="$repo_root/flake.nix"

if ! command -v nix &>/dev/null; then
  echo "Error: nix is not installed." >&2
  echo "Please install Nix from https://nixos.org/download.html" >&2
  exit 1
fi

nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

get_version() {
  sed -n "s/.*$1 = \"\([^\"]*\)\".*/\1/p" "$flake"
}

json_hash() { sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'; }

bonsai_version=$(get_version bonsaiVersion)
wine_version=$(get_version wineVersion)
nvidia_libs_version=$(get_version nvidiaLibsVersion)

# Wine tarballs for X.0 releases live under X.0/, later ones under X.x/.
wine_major=${wine_version%%.*}
wine_minor=${wine_version#*.}
if [ "$wine_minor" = "0" ]; then wine_dir="$wine_major.0"; else wine_dir="$wine_major.x"; fi

bonsai_hash=$(nix store prefetch-file --json \
  "https://github.com/bonsai-rx/bonsai/releases/download/$bonsai_version/Bonsai-$bonsai_version.exe" | json_hash)

wine_hash=$(nix store prefetch-file --json \
  "https://dl.winehq.org/wine/source/$wine_dir/wine-$wine_version.tar.xz" | json_hash)

staging_hash=$(nix flake prefetch --json \
  "github:wine-staging/wine-staging/v$wine_version" | json_hash)

nvidia_libs_hash=$(nix store prefetch-file --json \
  "https://github.com/SveSop/nvidia-libs/releases/download/v$nvidia_libs_version/nvidia-libs-v$nvidia_libs_version.tar.xz" | json_hash)

printf 'wineStagingSha256 = "%s";\n' "$staging_hash"
printf 'wineSha256 = "%s";\n' "$wine_hash"
printf 'bonsaiSha256 = "%s";\n' "$bonsai_hash"
printf 'nvidiaLibsSha256 = "%s";\n' "$nvidia_libs_hash"

cuda_redist="$repo_root/nix/cuda-redist.nix"
cuda_mirror=$(sed -n 's/.*mirror ? "\([^"]*\)".*/\1/p' "$cuda_redist")
sed -n 's/.*path = "\([^"]*\)".*/\1/p' "$cuda_redist" | while read -r path; do
  hash=$(nix store prefetch-file --json "$cuda_mirror/$path" | json_hash)
  printf '%s: sha256 = "%s";\n' "${path%%/*}/${path##*/}" "$hash"
done
