# Official python.org Windows (amd64) installer, fetched for installation into the Wine prefix
# by bonsai-setup. The installer is a WiX burn bundle that runs unattended with /quiet.
#
# Bonsai.Scripting.Python locates the runtime by searching PATH for python.exe and derives the
# DLL name (python312.dll) from the install directory's leaf name (Python312), so the installer
# must keep its default TargetDir layout and PrependPath=1.
{ lib
, fetchurl
}:

{ version
, sha256
, mirror ? "https://www.python.org/ftp/python"
}:

fetchurl {
  name = "python-${version}-amd64.exe";
  url = "${mirror}/${version}/python-${version}-amd64.exe";
  hash = sha256;

  passthru = {
    inherit version;
    # Install directory leaf as created by InstallAllUsers=1, e.g. Python312.
    homeDirName = "Python" + lib.concatStrings (lib.take 2 (lib.splitString "." version));
  };

  meta = {
    description = "Python ${version} Windows installer for Wine prefixes";
    homepage = "https://www.python.org/";
    license = lib.licenses.psfl;
    platforms = lib.platforms.all;
  };
}
