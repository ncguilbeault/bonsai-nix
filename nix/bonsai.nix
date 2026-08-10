{ lib
, fetchurl
, symlinkJoin
, writeShellScriptBin
, wine
}:

{ version ? "2.9.0"
, sha256 ? "sha256-jL7m+I54h/f6mfEBooYze3TYp8aXofgQ1z0uB9GTmzs="
, mirror ? "https://github.com/bonsai-rx/bonsai/releases/download"
, prefixName ? "bonsai"
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
  # pick up the NVML builtin from WINEDLLPATH (exported by the wine shims).
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

  setup = writeShellScriptBin "bonsai-setup" ''
    set -euo pipefail

    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    export WINEARCH=${lib.escapeShellArg wineArch}
    mkdir -p "$WINEPREFIX"

    ${envExports}

    export PATH="${wine}/bin:$PATH"

    boot_marker="$WINEPREFIX/.bonsai-booted"
    if [ ! -e "$boot_marker" ]; then
      echo "bonsai-setup: initializing prefix at $WINEPREFIX"
      WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1
      touch "$boot_marker"
    fi

    ${winetricksBlock}

    ${nvidiaLibsBlock}

    ${cudaRedistBlock}

    install_marker="$WINEPREFIX/.bonsai-installed-${version}"
    if [ ! -e "$install_marker" ]; then
      echo "bonsai-setup: installing Bonsai ${version} from ${installer}"
      wine ${lib.escapeShellArg installer} ${lib.concatStringsSep " " (map lib.escapeShellArg installerArgs)}
      touch "$install_marker"
    fi

    echo "bonsai-setup: ready (prefix: $WINEPREFIX)"
  '';

  launch = writeShellScriptBin "bonsai" ''
    set -euo pipefail

    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    export WINEARCH=${lib.escapeShellArg wineArch}
    mkdir -p "$WINEPREFIX"

    ${envExports}

    export PATH="${wine}/bin:$PATH"

    install_marker="$WINEPREFIX/.bonsai-installed-${version}"
    if [ ! -e "$install_marker" ]${
      lib.optionalString (nvidiaLibs != null) " || [ ! -e \"$WINEPREFIX/.bonsai-nvlibs-${nvidiaLibs.version}\" ]"
    }${
      lib.optionalString (cudaRedist != null) " || [ ! -e \"$WINEPREFIX/.bonsai-cuda-redist-${cudaRedist.version}\" ]"
    }; then
      echo "bonsai: prefix not initialized; running bonsai-setup..."
      ${setup}/bin/bonsai-setup
    else
      exec wine bonsai "$@"
    fi
  '';
in

symlinkJoin {
  name = "bonsai-${version}";
  paths = [ setup launch ] ++ lib.optional bundleWine wine;

  passthru = {
    inherit installer wine version nvidiaLibs cudaRedist;
  };

  meta = {
    description = "Bonsai-rx ${version} installed into a Wine prefix";
    homepage = "https://bonsai-rx.org/";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "bonsai";
  };
}
