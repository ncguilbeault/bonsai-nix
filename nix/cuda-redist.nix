# Windows CUDA toolkit runtime redistributables for use inside a Wine prefix.
# Fetches the official NVIDIA per-component redist archives and collects their
# 64-bit DLLs (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN) under $out/x64.
# These are the toolkit-level libraries that CUDA applications such as ONNX
# Runtime's CUDA execution provider expect next to the application or in
# system32; they are plain PE code that calls down into nvcuda.dll, which
# nvidia-libs routes to the host driver.
#
# The component archives and their hashes are pinned per release in
# nix/releases.nix. Hashes come from NVIDIA's redist manifests
# (https://developer.download.nvidia.com/compute/cuda/redist/ and
# .../compute/cudnn/redist/).

{ lib
, fetchurl
, stdenvNoCC
, unzip
}:

{ version
# Archives to fetch, each { name; path; sha256; } with path relative to the mirror.
, components
, mirror ? "https://developer.download.nvidia.com/compute"
}:

stdenvNoCC.mkDerivation {
  pname = "cuda-redist-wine";
  inherit version;

  srcs = map (c: fetchurl {
    url = "${mirror}/${c.path}";
    hash = c.sha256;
  }) components;

  nativeBuildInputs = [ unzip ];

  buildCommand = ''
    mkdir -p "$out/x64" extracted
    for src in $srcs; do
      unzip -q "$src" -d extracted
    done
    find extracted -path '*/bin/*' -name '*.dll' -exec cp {} "$out/x64/" \;
  '';

  meta = {
    description = "Windows CUDA runtime and cuDNN DLLs (official NVIDIA redistributables) for Wine prefixes";
    homepage = "https://developer.nvidia.com/cuda-toolkit";
    platforms = [ "x86_64-linux" ];
  };
}
