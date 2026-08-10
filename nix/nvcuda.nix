# SveSop/nvcuda built from source: the Wine nvcuda.dll thunk that forwards the CUDA driver
# API to the host libcuda. The nvidia-libs release bundle ships this DLL only as a prebuilt
# binary; building it from source allows local patches to be applied (see the patches/
# directory). The output layout (x64/nvcuda.dll) matches the bundle so nix/nvidia-libs.nix
# can overlay it directly.

{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, writeText
}:

{ wineTools
, rev ? "772b344a3594fca916999c5c5288d875332de482"
, sha256 ? "sha256-2WRu93anAO/qxnwoTE+jKuEYPhqdQKUFF0OcScFpgZU="
, patches ? [ ]
}:

let
  # Mirrors the cross file shipped as build-wine64.txt in the nvcuda repository, with the
  # compiler pinned to the same wine build the prefix runs.
  crossFile = writeText "nvcuda-wine64-cross.txt" ''
    [binaries]
    c = '${wineTools}/bin/winegcc'
    ar = 'ar'
    strip = 'strip'

    [built-in options]
    c_args = ['-m64', '--no-gnu-unique', '-D__WINESRC__']
    c_link_args = ['-m64', '-mwindows']

    [properties]
    needs_exe_wrapper = true
    winelib = true

    [host_machine]
    system = 'linux'
    cpu_family = 'x86_64'
    cpu = 'x86_64'
    endian = 'little'
  '';
in

stdenv.mkDerivation {
  pname = "nvcuda";
  version = "0.3-unstable-${lib.substring 0 7 rev}";

  src = fetchFromGitHub {
    owner = "SveSop";
    repo = "nvcuda";
    inherit rev;
    hash = sha256;
  };

  inherit patches;

  nativeBuildInputs = [ meson ninja wineTools ];

  mesonFlags = [ "--cross-file=${crossFile}" ];

  # meson's install target lays the module out for a wine build tree; the flat winelib
  # DLL is all the nvidia-libs bundle needs.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/x64"
    cp dlls/nvcuda/nvcuda.dll.so "$out/x64/nvcuda.dll"
    runHook postInstall
  '';

  meta = {
    description = "CUDA driver API thunk for Wine, built from source (x86_64 winelib)";
    homepage = "https://github.com/SveSop/nvcuda";
    platforms = [ "x86_64-linux" ];
  };
}
