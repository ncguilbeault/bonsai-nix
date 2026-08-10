# SveSop/nvidia-libs release bundle: Wine libraries for NVIDIA CUDA, NVENC/NVDEC, NVML, OptiX and NvAPI.
# The output is the unpacked release tarball (x64/, x32/, layer/, setup scripts). Several of the
# x64 DLLs are ELF winelib modules that dlopen the host driver libraries (libcuda.so.1, libnvcuvid.so.1,
# libnvidia-encode.so.1) at runtime, so the driver libraries must be resolvable via LD_LIBRARY_PATH.

{ lib
, fetchurl
, stdenvNoCC
}:

{ version ? "1.0.2"
, sha256 ? "sha256-Aei7Y2jQiOItjo8dAklyFOjbQ2R2Ahcl7wwHB7fLFzg="
, mirror ? "https://github.com/SveSop/nvidia-libs/releases/download"
# Optional source-built nvcuda derivation (see nix/nvcuda.nix); when set, its
# x64/nvcuda.dll replaces the prebuilt one and the bundle version is suffixed so
# prefix setup markers re-run and re-point the system32 symlinks.
, nvcuda ? null
}:

stdenvNoCC.mkDerivation {
  pname = "nvidia-libs";
  version = if nvcuda == null then version else "${version}+nvcuda-${nvcuda.version}";

  src = fetchurl {
    url = "${mirror}/v${version}/nvidia-libs-v${version}.tar.xz";
    hash = sha256;
  };

  # The DLLs are prebuilt Wine modules (PE and ELF); leave them byte-identical.
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    mkdir -p "$out"
    cp -r . "$out"
  '' + lib.optionalString (nvcuda != null) ''
    chmod u+w "$out/x64"
    rm -f "$out/x64/nvcuda.dll"
    install -m755 ${nvcuda}/x64/nvcuda.dll "$out/x64/nvcuda.dll"
  '';

  meta = {
    description = "CUDA, NVENC/NVDEC, NVML, OptiX and NvAPI libraries for Wine (prebuilt release)";
    homepage = "https://github.com/SveSop/nvidia-libs";
    platforms = [ "x86_64-linux" ];
  };
}
