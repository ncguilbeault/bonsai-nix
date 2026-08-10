# Windows CUDA toolkit runtime redistributables for use inside a Wine prefix.
# Fetches the official NVIDIA per-component redist archives and collects their
# 64-bit DLLs (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN) under $out/x64.
# These are the toolkit-level libraries that CUDA applications such as ONNX
# Runtime's CUDA execution provider expect next to the application or in
# system32; they are plain PE code that calls down into nvcuda.dll, which
# nvidia-libs routes to the host driver.
#
# Component pins target CUDA 12.x (cudart64_12/cublas64_12), matching ONNX
# Runtime GPU builds up to 1.22 and current cuDNN 9. Hashes come from NVIDIA's
# redist manifests (https://developer.download.nvidia.com/compute/cuda/redist/
# and .../compute/cudnn/redist/); scripts/fetch-hashes.sh can regenerate them.

{ lib
, fetchurl
, stdenvNoCC
, unzip
}:

{ version ? "12.8-cudnn9.25.0"
, mirror ? "https://developer.download.nvidia.com/compute"
, components ? [
    {
      name = "cuda_cudart";
      path = "cuda/redist/cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-12.8.90-archive.zip";
      sha256 = "sha256-SjkFj9hRlESoHPx64FXRNvSNGjH/pBriVbNbLt1h4Ts=";
    }
    {
      name = "libcublas";
      path = "cuda/redist/libcublas/windows-x86_64/libcublas-windows-x86_64-12.8.4.1-archive.zip";
      sha256 = "sha256-V6RwESzsfhEslSU93os8cYTXldvZKwved6TLf4yUyKo=";
    }
    {
      name = "libcufft";
      path = "cuda/redist/libcufft/windows-x86_64/libcufft-windows-x86_64-11.3.3.83-archive.zip";
      sha256 = "sha256-zG4LqVjPIzh7RiAXokRkxyvZAVSQRhM/PR68w9dETJA=";
    }
    {
      name = "libcurand";
      path = "cuda/redist/libcurand/windows-x86_64/libcurand-windows-x86_64-10.3.9.90-archive.zip";
      sha256 = "sha256-RuujbCB0iyGlkntWm5QzN90YSFEyEZ37OaW82k7bEuI=";
    }
    {
      name = "cuda_nvrtc";
      path = "cuda/redist/cuda_nvrtc/windows-x86_64/cuda_nvrtc-windows-x86_64-12.8.93-archive.zip";
      sha256 = "sha256-pjMCoHfwJIp0Ohp8qn29gND6xWxs+pxB+gX6ybfl7aU=";
    }
    {
      name = "cudnn";
      path = "cudnn/redist/cudnn/windows-x86_64/cudnn-windows-x86_64-9.25.0.15_cuda12-archive.zip";
      sha256 = "sha256-BulPcMUtczW37YBE7tKM6WO3/VnYwsRG/8YOaV/MrZE=";
    }
  ]
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
