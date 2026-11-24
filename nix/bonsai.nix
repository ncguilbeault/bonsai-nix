{ lib
, stdenv
, fetchurl
, symlinkJoin
, writeShellScriptBin
, wine
}:

{ version
, sha256
, mirror ? "https://github.com/bonsai-rx/bonsai/releases/download"
, prefixName ? "bonsai"
# Appended to the command names (e.g. "-2.9.0" gives bonsai-2.9.0 and
# bonsai-setup-2.9.0 and bonsai-wine-2.9.0), so that several versions can be installed side by side.
, binSuffix ? ""
, wineArch ? "win64"
, winetricksVerbs ? [ "dotnet48" "allfonts" "gdiplus" ]
, winetricksArgs ? [ ]
, winetricksMarkerTag ? "default"
, installerArgs ? [ ]
, extraEnv ? { WINEDEBUG = "-all"; }
, bundleWine ? true
, prefixPath ? "$HOME/.local/share/wineprefixes"
, nvidiaLibs ? null
, cudaRedist ? null
, python ? null
, pythonInstallerArgs ? [ "/quiet" "InstallAllUsers=1" "PrependPath=1" "Include_test=0" "Include_launcher=0" ]
, pythonPackages ? [ ]
}:

let
  installer = fetchurl {
    url = "${mirror}/${version}/Bonsai-${version}.exe";
    hash = "${sha256}";
  };

  envExports = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") extraEnv);

  winetricksBlock = lib.optionalString (winetricksVerbs != [ ] || winetricksArgs != [ ]) ''
    if ! command -v winetricks >/dev/null 2>&1; then
      echo "bonsai-setup: winetricks not found on PATH" >&2
      exit 1
    fi

    tricks_marker="$WINEPREFIX/.bonsai-winetricks-${winetricksMarkerTag}"
    if [ ! -e "$tricks_marker" ]; then
      echo "bonsai-setup: running winetricks (${lib.concatStringsSep " " winetricksVerbs})"
      winetricks -q ${lib.concatStringsSep " " (map lib.escapeShellArg winetricksArgs)} \
        ${lib.concatStringsSep " " (map lib.escapeShellArg winetricksVerbs)}
      touch "$tricks_marker"
    fi
  '';

  # Installs nvidia-libs into the prefix the same way upstream's setup_nvlibs.sh does:
  # a native DLL override plus a symlink into the prefix's system directory for every
  # bundled DLL. Symlinks point into the Nix store, so a version bump re-runs the block
  # (marker is version-tagged) and ln -sf re-points them. The trailing wineboot lets wine
  # pick up the NVML builtin from WINEDLLPATH.
  nvidiaLibsBlock = lib.optionalString (nvidiaLibs != null) ''
    nvlibs_marker="$WINEPREFIX/.bonsai-nvlibs-${nvidiaLibs.version}"
    if [ ! -e "$nvlibs_marker" ]; then
      echo "bonsai-setup: installing nvidia-libs ${nvidiaLibs.version}"
      for dll in ${nvidiaLibs}/x64/*.dll; do
        [ -e "$dll" ] || continue
        name="$(basename "$dll" .dll)"
        wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$name" /d native /f >/dev/null
        ln -sf "$dll" "$WINEPREFIX/drive_c/windows/system32/$name.dll"
      done
      if [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
        for dll in ${nvidiaLibs}/x32/*.dll; do
          [ -e "$dll" ] || continue
          name="$(basename "$dll" .dll)"
          wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$name" /d native /f >/dev/null
          ln -sf "$dll" "$WINEPREFIX/drive_c/windows/syswow64/$name.dll"
        done
      fi
      wineboot -u
      touch "$nvlibs_marker"
    fi
  '';

  # Installs the Windows CUDA toolkit runtime DLLs (cudart, cuBLAS, cuDNN, ...) into
  # the prefix's system32. Unlike nvidia-libs these need no registry overrides (wine has
  # no builtins for them); a symlink into the DLL search path is enough for applications
  # such as ONNX Runtime's CUDA provider to load them.
  cudaRedistBlock = lib.optionalString (cudaRedist != null) ''
    cuda_redist_marker="$WINEPREFIX/.bonsai-cuda-redist-${cudaRedist.version}"
    if [ ! -e "$cuda_redist_marker" ]; then
      echo "bonsai-setup: installing CUDA runtime ${cudaRedist.version}"
      for dll in ${cudaRedist}/x64/*.dll; do
        [ -e "$dll" ] || continue
        ln -sf "$dll" "$WINEPREFIX/drive_c/windows/system32/$(basename "$dll")"
      done
      touch "$cuda_redist_marker"
    fi
  '';

  # Runs the python.org installer unattended inside the prefix. With InstallAllUsers=1 and
  # PrependPath=1 it lands in C:\Program Files\Python<XY> and prepends itself to the system
  # PATH in the registry, which is how Bonsai.Scripting.Python locates the runtime. The
  # marker is version-tagged so a version bump installs the new release alongside the old
  # one. pythonPackages are installed with pip afterwards under a marker keyed on the list,
  # so changing the list re-runs pip (already satisfied packages are skipped).
  pythonBlock = lib.optionalString (python != null) ''
    python_marker="$WINEPREFIX/.bonsai-python-${python.version}"
    if [ ! -e "$python_marker" ]; then
      echo "bonsai-setup: installing Python ${python.version}"
      wine ${lib.escapeShellArg python} ${lib.concatStringsSep " " (map lib.escapeShellArg pythonInstallerArgs)}
      wineserver -w
      touch "$python_marker"
    fi
  '' + lib.optionalString (python != null && pythonPackages != [ ]) ''
    pip_marker="$WINEPREFIX/.bonsai-python-${python.version}-pip-${builtins.hashString "sha256" (lib.concatStringsSep " " pythonPackages)}"
    if [ ! -e "$pip_marker" ]; then
      echo "bonsai-setup: installing Python packages (${lib.concatStringsSep " " pythonPackages})"
      wine 'C:\Program Files\${python.homeDirName}\python.exe' -m pip install --no-input \
        ${lib.concatStringsSep " " (map lib.escapeShellArg pythonPackages)}
      touch "$pip_marker"
    fi
  '';

  # nvidia-libs runtime environment: WINEDLLPATH lets wine pick up the NVML builtin
  # (nvml.dll/nvml.so), and the ELF winelib modules (nvcuda, nvcuvid, ...) dlopen the
  # host NVIDIA driver libraries, which live under /run/opengl-driver/lib on NixOS.
  nvidiaLibsEnv = lib.optionalString (nvidiaLibs != null) ''
    export WINEDLLPATH="${nvidiaLibs}/x64/wine''${WINEDLLPATH:+:$WINEDLLPATH}"
    if [ -d /run/opengl-driver/lib ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
  '';

  # Shared preamble of every script: the prefix, the environment and this build's Wine on PATH.
  envSetup = ''
    set -euo pipefail

    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    export WINEARCH=${lib.escapeShellArg wineArch}
    mkdir -p "$WINEPREFIX"

    ${envExports}
    ${nvidiaLibsEnv}
    export PATH="${wine}/bin:$PATH"
  '';

  # Runs a command in the environment the launcher uses, so that Wine tools act on this
  # prefix with this build's Wine: bonsai-wine winecfg, bonsai-wine winetricks <verb>,
  # bonsai-wine wine reg query ...
  wineRun = writeShellScriptBin "bonsai-wine${binSuffix}" ''
    if [ $# -eq 0 ]; then
      echo "usage: bonsai-wine${binSuffix} <command> [args...]" >&2
      exit 1
    fi

    ${envSetup}

    exec "$@"
  '';

  setup = writeShellScriptBin "bonsai-setup${binSuffix}" ''
    ${envSetup}

    boot_marker="$WINEPREFIX/.bonsai-booted"
    if [ ! -e "$boot_marker" ]; then
      echo "bonsai-setup: initializing prefix at $WINEPREFIX"
      WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1
      touch "$boot_marker"
    fi

    ${winetricksBlock}

    ${nvidiaLibsBlock}

    ${cudaRedistBlock}

    ${pythonBlock}

    install_marker="$WINEPREFIX/.bonsai-installed-${version}"
    if [ ! -e "$install_marker" ]; then
      echo "bonsai-setup: installing Bonsai ${version} from ${installer}"
      wine ${lib.escapeShellArg installer} ${lib.concatStringsSep " " (map lib.escapeShellArg installerArgs)}
      touch "$install_marker"
    fi

    # Temporary workaround: Wine >= 10.17 implements WGL through EGL in the X11 driver by default, and on the NVIDIA proprietary driver the EGL path exposes no pixel formats that OpenTK accepts, so Bonsai.Shaders window creation fails with "The requested GraphicsMode is not supported". Force the GLX backend until the EGL path works on NVIDIA (see opentk/opentk#523).
    wine reg add 'HKCU\Software\Wine\X11 Driver' /v UseEGL /t REG_SZ /d N /f >/dev/null

    echo "bonsai-setup: ready (prefix: $WINEPREFIX)"
  '';

  launch = writeShellScriptBin "bonsai${binSuffix}" ''
    ${envSetup}

    install_marker="$WINEPREFIX/.bonsai-installed-${version}"
    if [ ! -e "$install_marker" ]${
      lib.optionalString (nvidiaLibs != null) " || [ ! -e \"$WINEPREFIX/.bonsai-nvlibs-${nvidiaLibs.version}\" ]"
    }${
      lib.optionalString (cudaRedist != null) " || [ ! -e \"$WINEPREFIX/.bonsai-cuda-redist-${cudaRedist.version}\" ]"
    }${
      lib.optionalString (python != null) " || [ ! -e \"$WINEPREFIX/.bonsai-python-${python.version}\" ]"
    }; then
      echo "bonsai: prefix not initialized; running bonsai-setup..."
      ${setup}/bin/bonsai-setup${binSuffix}
    else
      exec wine bonsai "$@"
    fi
  '';
in

assert lib.assertMsg (nvidiaLibs == null || !stdenv.hostPlatform.isDarwin)
  "bonsai-nix: nvidia-libs dlopens the Linux NVIDIA driver and cannot work on macOS; use the non-cuda packages instead.";
symlinkJoin {
  name = "bonsai-${version}";
  paths = [ setup launch wineRun ] ++ lib.optional bundleWine wine;

  passthru = {
    inherit installer wine version nvidiaLibs cudaRedist python;
  };

  meta = {
    description = "Bonsai-rx ${version} installed into a Wine prefix";
    homepage = "https://bonsai-rx.org/";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "bonsai${binSuffix}";
  };
}
