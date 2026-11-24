# Release sets: each Bonsai version is pinned together with every dependency it is
# released against (Wine, nvidia-libs, nvcuda, the CUDA runtime and Python). A new
# release adds an entry here; the hashes are printed by scripts/fetch-hashes.sh.
# Dependency pins shared by several releases are bound once below and reused.
# nvcuda is optional: a release set without it uses the nvcuda.dll bundled with
# nvidia-libs instead of a source build.
let
  treeviewPatch = ../patches/0001-Remove-assertion-line-which-causes-crash-in-Bonsai-t.patch;
  nvcudaHostFuncPatch = ../patches/0002-nvcuda-relay-cuLaunchHostFunc-through-callback-worker.patch;

  wine_11_8 = {
    version = "11.8";
    sha256 = "sha256-U6qFmV1Ll/ARahxWuKahQXcw71mid4GdLT0xNk6lVrA=";
    stagingSha256 = "sha256-lW5dfCfsB+z84mlLpfmkR7QDxmhL+RcBufSftUutHto=";
    patches = [ treeviewPatch ];
  };

  wine_11_12 = {
    version = "11.12";
    sha256 = "sha256-07wJEZLZhYRsnyAGXMgfITMfAeIrc2sTHjRJ4TBmcbw=";
    stagingSha256 = "sha256-3pE/RVUvH56z9Ilumokl7nNMrhfksuUWzKq6k8behW4=";
    patches = [ treeviewPatch ];
  };

  nvidiaLibs_1_0_2 = {
    version = "1.0.2";
    sha256 = "sha256-Aei7Y2jQiOItjo8dAklyFOjbQ2R2Ahcl7wwHB7fLFzg=";
  };

  nvcuda_772b344 = {
    rev = "772b344a3594fca916999c5c5288d875332de482";
    sha256 = "sha256-2WRu93anAO/qxnwoTE+jKuEYPhqdQKUFF0OcScFpgZU=";
    patches = [ nvcudaHostFuncPatch ];
  };

  # CUDA 12.x (cudart64_12/cublas64_12) with cuDNN 9, matching ONNX Runtime GPU builds
  # up to 1.22. Component paths are relative to NVIDIA's redist mirror
  # (https://developer.download.nvidia.com/compute).
  cudaRedist_12_8 = {
    version = "12.8-cudnn9.25.0";
    components = [
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
    ];
  };

  python_3_12_10 = {
    version = "3.12.10";
    sha256 = "sha256-Z7VjXoDqUQcrh5QTEtAOyJJ8Tbm6GJOPetLSezKLlfs=";
  };
in
{
  "2.9.0" = {
    bonsai.sha256 = "sha256-jL7m+I54h/f6mfEBooYze3TYp8aXofgQ1z0uB9GTmzs=";
    wine = wine_11_8;
    nvidiaLibs = nvidiaLibs_1_0_2;
    nvcuda = nvcuda_772b344;
    cudaRedist = cudaRedist_12_8;
    python = python_3_12_10;
  };

  "2.9.1" = {
    bonsai.sha256 = "sha256-d3b5oOZTiLlDgLPLlMHJyXdqBvuN+6WlcYDnVpS08NI=";
    wine = wine_11_12;
    nvidiaLibs = nvidiaLibs_1_0_2;
    nvcuda = nvcuda_772b344;
    cudaRedist = cudaRedist_12_8;
    python = python_3_12_10;
  };
}
