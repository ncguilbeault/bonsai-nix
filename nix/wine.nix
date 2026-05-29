{ lib
, pkgs
, fetchurl
, symlinkJoin
, writeShellScriptBin
, winetricks
}:

{ version ? "11.0"
, sha256 ? "sha256-wHpoV5M8H8YN/1RI1585ySSBwenbWqYo250DWERuBwE="
, variant ? "full"
, mirror ? "https://dl.winehq.org/wine/source"
, prefixName ? "wine"
, patches ? [ ]
, replaceUpstreamPatches ? false
, withWinetricks ? true
, extraEnv ? { }
, prefixPath ? "$HOME/.local/share/wineprefixes"
, stagingSrc ? null
}:

let
  baseFor = v:
    let
      table = with pkgs; {
        "full"        = wineWow64Packages.full;
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
      pkgs.python3 pkgs.bash pkgs.git pkgs.perl
      pkgs.autoconf pkgs.automake pkgs.libtool
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

  envExports = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") extraEnv);

  # Shared preamble for every wine-family shim: set up WINEPREFIX, env, PATH.
  envSetup = ''
    set -euo pipefail
    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    mkdir -p "$WINEPREFIX"
    ${envExports}
    export PATH="${wineHQ}/bin:$PATH"
  '';

  mkWineShim = name: writeShellScriptBin name ''
    ${envSetup}
    exec "${wineHQ}/bin/${name}" "$@"
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

  # winetricks shim: forces it to use this wine, with a sane WINEPREFIX default.
  winetricksShim = writeShellScriptBin "winetricks" ''
    ${envSetup}
    export WINETRICKS_WINE="${wineHQ}/bin/wine"
    exec ${winetricks}/bin/winetricks "$@"
  '';
in

symlinkJoin {
  name = "wine-${version}";
  paths = binShims ++ lib.optional withWinetricks winetricksShim;

  passthru = {
    inherit wineHQ version variant;
  };

  meta = {
    description = "Patched Wine ${version} (${variant})";
    platforms = lib.platforms.linux;
    mainProgram = "wine";
  };
}
