{ lib
, pkgs
, buildFHSEnv
, fetchurl
, symlinkJoin
, writeShellScript
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
, extraFhsPackages ? [ ]
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

  fhsEnv = buildFHSEnv {
    name = "wine-fhs";

    targetPkgs = p: (with p; [
      coreutils
      findutils
      gnugrep
      gawk
      which
      file

      # Common runtime deps
      glib
      zlib
      gcc.cc.lib
      openssl
      cups
      fontconfig
      freetype
      expat

      # X11 stack
      libx11
      libxext
      libxrender
      libxrandr
      libxi
      libxcursor
      libxfixes
      libxinerama
      libxcomposite
      libxdamage

      # Wayland
      wayland
      libxkbcommon

      # GL / Vulkan
      libglvnd
      mesa
      vulkan-loader
    ]) ++ extraFhsPackages;

    runScript = writeShellScript "wine-fhs-run" ''
      set -euo pipefail

      : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
      export WINEPREFIX
      mkdir -p "$WINEPREFIX"

      ${envExports}

      bin=wine
      if [ "''${1-}" = "--__wine-bin" ]; then
        shift
        if [ "$#" -lt 1 ]; then
          echo "wine-fhs: missing binary name after --__wine-bin" >&2
          exit 2
        fi
        bin="$1"
        shift
      fi

      if [ ! -x "${wineHQ}/bin/$bin" ]; then
        echo "wine-fhs: '${wineHQ}/bin/$bin' not found or not executable" >&2
        exit 127
      fi

      export PATH="${wineHQ}/bin:$PATH"
      exec "${wineHQ}/bin/$bin" "$@"
    '';
  };

  # Primary wine entrypoint: invokes the FHS wrapper directly (default = wine binary).
  wineCmd = writeShellScriptBin "wine" ''
    exec ${fhsEnv}/bin/wine-fhs "$@"
  '';

  # Each alias dispatches to a different wine binary inside the same FHS env.
  mkAlias = name: writeShellScriptBin name ''
    exec ${fhsEnv}/bin/wine-fhs --__wine-bin ${name} "$@"
  '';

  aliasNames = [
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

  binAliases = map mkAlias aliasNames;

  # winetricks shim: forces it to use this FHS-wrapped wine, with a sane WINEPREFIX default.
  winetricksShim = writeShellScriptBin "winetricks" ''
    set -euo pipefail
    : "''${WINEPREFIX:=${prefixPath}/${prefixName}}"
    export WINEPREFIX
    mkdir -p "$WINEPREFIX"

    ${envExports}

    export PATH="${wineHQ}/bin:$PATH"
    export WINETRICKS_WINE="${fhsEnv}/bin/wine-fhs"
    exec ${winetricks}/bin/winetricks "$@"
  '';
in

symlinkJoin {
  name = "wine-${version}";
  paths = [ wineCmd ] ++ binAliases ++ lib.optional withWinetricks winetricksShim;

  passthru = {
    inherit wineHQ fhsEnv version variant;
    fhsCommand = "${fhsEnv}/bin/wine-fhs";
  };

  meta = {
    description = "Patched Wine ${version} (${variant}) wrapped in an FHS env";
    platforms = lib.platforms.linux;
    mainProgram = "wine";
  };
}
