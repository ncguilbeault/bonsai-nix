# MinGit: the minimal Git for Windows distribution intended for use by other programs. The
# output is the unpacked release archive, with git.exe under cmd/. It is not installed into
# the Wine prefix: the Bonsai commands put its cmd directory on the prefix's PATH through
# WINEPATH, so that programs run in the prefix (pip, uv) find a git to fetch
# git+https:// dependencies with.
{ lib
, fetchurl
, stdenvNoCC
, unzip
}:

{ version
, sha256
, mirror ? "https://github.com/git-for-windows/git/releases/download"
}:

let
  # A Git for Windows release is tagged v<git version>.windows.<n>. Its archive is named
  # after the Git version alone for n = 1 and after <git version>.<n> otherwise, so a
  # version of three components is build 1 and a fourth component is the build number.
  parts = lib.splitVersion version;
  tag = "v${lib.concatStringsSep "." (lib.take 3 parts)}.windows.${if lib.length parts > 3 then lib.elemAt parts 3 else "1"}";
in
stdenvNoCC.mkDerivation {
  pname = "mingit";
  inherit version;

  src = fetchurl {
    url = "${mirror}/${tag}/MinGit-${version}-64-bit.zip";
    hash = sha256;
  };

  nativeBuildInputs = [ unzip ];

  # The executables are prebuilt Windows binaries; leave them byte-identical.
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    unzip -q "$src" -d source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    cp -r source "$out"
    runHook postInstall
  '';

  meta = {
    description = "MinGit ${version}, a minimal Git for Windows for Wine prefixes";
    homepage = "https://gitforwindows.org/";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.all;
  };
}
