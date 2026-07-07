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
    if [ ! -e "$install_marker" ]; then
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
    inherit installer wine version;
  };

  meta = {
    description = "Bonsai-rx ${version} installed into a Wine prefix";
    homepage = "https://bonsai-rx.org/";
    platforms = lib.platforms.linux;
    mainProgram = "bonsai";
  };
}
