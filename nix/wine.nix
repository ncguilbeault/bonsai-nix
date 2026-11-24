{ lib
, pkgs
, fetchurl
, runCommand
, runtimeShell
, symlinkJoin
, writeShellScriptBin
, winetricks
}:

{ version
, sha256
, variant ? "full"
, mirror ? "https://dl.winehq.org/wine/source"
, # Default WINEPREFIX of the shims is prefixPath/prefixName; when null they leave
# WINEPREFIX alone, so Wine falls back to its own default.
prefixName ? null
# Appended to every command name (e.g. "-11.22" gives wine-11.22 and winecfg-11.22),
# so that several Wine versions can be installed side by side.
, binSuffix ? ""
, patches ? [ ]
, replaceUpstreamPatches ? false
, withWinetricks ? true
, extraEnv ? { }
, prefixPath ? "$HOME/.local/share/wineprefixes"
, stagingSrc ? null
, emulator ? null
, winePkgs ? pkgs
}:

let
  isMac = pkgs.stdenv.hostPlatform.isDarwin;

  # zenity only serves winetricks' GUI mode but drags the GTK/libadwaita/appstream
  # stack into the closure, which does not build on darwin; stub it out there and
  # let winetricks run in console mode.
  winetricks' = if isMac then winetricks.override { zenity = pkgs.emptyDirectory; } else winetricks;

  baseFor = v:
    let
      # The wayland variant is meaningless on macOS, where wine draws via the Mac/X11 drivers.
      table = with winePkgs; {
        "full" = wineWow64Packages.full;
      } // lib.optionalAttrs (!isMac) {
        "waylandFull" = wineWow64Packages.waylandFull;
      };
    in
      table.${v}
      or (throw "wine variant '${v}' unknown; valid: ${lib.concatStringsSep ", " (lib.attrNames table)}");

  major = lib.head (lib.splitString "." version);

  # If minor version is 0, then the stable release is in {major}.0, otherwise it's in {major}.{minor}.
  minor = let
    parts = lib.splitString "." version;
    minorPart = lib.head (lib.tail parts);
  in
    if minorPart == "0" then "0" else "x";

  src = fetchurl {
    url = "${mirror}/${major}.${minor}/wine-${version}.tar.xz";
    hash = "${sha256}";
  };

  wineHQ = (baseFor variant).overrideAttrs (old: {
    pname = old.pname or "wine";
    inherit version src;

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      winePkgs.python3 winePkgs.bash winePkgs.git winePkgs.perl
      winePkgs.autoconf winePkgs.automake winePkgs.libtool
    ];

    prePatch = (if old.prePatch or null != null then old.prePatch else "")
      + lib.optionalString (stagingSrc != null) ''
        cp -r ${stagingSrc} ./wine-staging-src
        chmod -R u+w ./wine-staging-src
        patchShebangs ./wine-staging-src/staging/patchinstall.py ./wine-staging-src/patches/gitapply.sh
        patchShebangs ./tools
        ./wine-staging-src/staging/patchinstall.py DESTDIR="$PWD" --all
      '';

    patches =
      let
        upstream = old.patches or [ ];
        # When applying the wine-staging patchset ourselves, drop any nixpkgs
        # patches that overlap with it (staging is a superset).
        filtered =
          if stagingSrc != null
          then lib.filter (p: !lib.hasInfix "add-dll-accept-device-paths" (toString p)) upstream
          else upstream;
      in
        if replaceUpstreamPatches then patches else filtered ++ patches;

    postInstall = (old.postInstall or "") + ''
      if [ ! -e "$out/bin/wine64" ] && [ -f "$out/bin/wine" ]; then
        ln -s "$out/bin/wine" "$out/bin/wine64"
      fi
    '';
  });

  # On emulated hosts, wrap every wine binary so native processes can exec it.
  wineBinDir =
    if emulator == null then "${wineHQ}/bin"
    else "${runCommand "wine-${version}-emulated" { } ''
      mkdir -p "$out/bin"
      for exe in ${wineHQ}/bin/*; do
        wrapper="$out/bin/$(basename "$exe")"
        echo '#!${runtimeShell}' > "$wrapper"
        echo "exec ${emulator} \"$exe\" \"\$@\"" >> "$wrapper"
        chmod +x "$wrapper"
      done
    ''}/bin";

  envExports = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") extraEnv);

  # Shared preamble for every wine-family shim: set up WINEPREFIX, env, PATH.
  envSetup = ''
    set -euo pipefail
  '' + lib.optionalString (prefixName != null) ''
    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    mkdir -p "$WINEPREFIX"
  '' + ''
    ${envExports}
    export PATH="${wineBinDir}:$PATH"
  '';

  mkWineShim = name: writeShellScriptBin "${name}${binSuffix}" ''
    ${envSetup}
    exec "${wineBinDir}/${name}" "$@"
  '';

  shimNames = [
    "wine"
    "wine64"
    "wineboot"
    "wineserver"
    "winecfg"
    "regedit"
    "wineconsole"
    "msiexec"
    "winefile"
    "notepad"
    "uninstaller"
    "winedbg"
  ];

  binShims = map mkWineShim shimNames;

  # winetricks shim: forces it to use this wine.
  winetricksShim = writeShellScriptBin "winetricks${binSuffix}" ''
    ${envSetup}
    export WINE="${wineBinDir}/wine"
    export WINESERVER="${wineBinDir}/wineserver"
    export WINETRICKS_WINE="${wineBinDir}/wine"
    exec ${winetricks'}/bin/winetricks "$@"
  '';
in

symlinkJoin {
  name = "wine-${version}";
  paths = binShims ++ lib.optional withWinetricks winetricksShim;

  passthru = {
    inherit wineHQ version variant emulator;
  };

  meta = {
    description = "Patched Wine ${version} (${variant})";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "wine${binSuffix}";
  };
}
