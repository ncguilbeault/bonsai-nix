self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.bonsai;

  wineSettings = {
    options = {
      version = lib.mkOption {
        type = lib.types.str;
        default = "11.0";
        description = "Wine version (e.g. 11.0). Used to fetch the WineHQ tarball.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = "wHpoV5M8H8YN/1RI1585ySSBwenbWqYo250DWERuBwE=";
        description = "SRI hash body for the WineHQ tarball (no 'sha256-' prefix).";
      };

      variant = lib.mkOption {
        type = lib.types.enum [ "wow-staging" "wow-full" "stable" "wayland" "wayland-full" ];
        default = "wow-full";
        description = "Base Wine variant from nixpkgs to override.";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://dl.winehq.org/wine/source";
        description = "Mirror for the WineHQ source tarball.";
      };

      patches = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Extra patches to apply on top of (or in place of) upstream Wine patches.";
      };

      replaceUpstreamPatches = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "If true, the patches list fully replaces upstream patches instead of appending.";
      };

      withWinetricks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include the winetricks shim in the wine package.";
      };

      extraFhsPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Extra packages to include in the Wine FHS environment.";
      };

      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables exported by the wine wrapper.";
      };
    };
  };

  bonsaiSettings = {
    options = {
      version = lib.mkOption {
        type = lib.types.str;
        default = "2.9.0";
        description = "Bonsai release version.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = "jL7m+I54h/f6mfEBooYze3TYp8aXofgQ1z0uB9GTmzs=";
        description = "SRI hash body for the Bonsai installer exe (no 'sha256-' prefix).";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/bonsai-rx/bonsai/releases/download";
        description = "Mirror for the Bonsai installer.";
      };

      prefixName = lib.mkOption {
        type = lib.types.str;
        default = "bonsai";
        description = "Wine prefix name under ~/.local/share/wineprefixes/.";
      };

      wineArch = lib.mkOption {
        type = lib.types.str;
        default = "win64";
        description = "WINEARCH for the prefix.";
      };

      winetricksVerbs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "dotnet48" "allfonts" "gdiplus" ];
        description = "Winetricks bundles/verbs to install in the prefix.";
      };

      winetricksArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments passed to winetricks before the verbs.";
      };

      winetricksMarkerTag = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Bump this tag to force a re-run of winetricks in existing prefixes.";
      };

      installerArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments passed to the Bonsai installer.";
      };

      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { WINEDEBUG = "-all"; };
        description = "Extra environment variables exported by bonsai-setup and bonsai.";
      };

      bundleWine = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If true, the bonsai package symlinks the wine package into its output.";
      };
    };
  };

  wineArgs = {
    inherit (cfg.wine)
      version sha256 variant mirror patches replaceUpstreamPatches
      withWinetricks extraFhsPackages extraEnv;
  };

  bonsaiArgs = {
    inherit (cfg.bonsai)
      version sha256 mirror prefixName wineArch
      winetricksVerbs winetricksArgs winetricksMarkerTag
      installerArgs extraEnv bundleWine;
  };

  winePackage = pkgs.callPackage "${self}/nix/wine.nix" { } wineArgs;

  bonsaiPackage = pkgs.callPackage "${self}/nix/bonsai.nix" {
    wine = winePackage;
  } bonsaiArgs;
in
{
  options.programs.bonsai = {
    enable = lib.mkEnableOption "Bonsai-rx via patched Wine";

    installWine = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to add the (patched) Wine package to home.packages.
        Disable if you bundle wine into the bonsai package and don't
        want a separate top-level entry.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The resolved Bonsai package (read-only).";
    };

    winePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The resolved Wine package (read-only).";
    };

    wine = lib.mkOption {
      type = lib.types.submodule wineSettings;
      default = { };
      description = "Wine build configuration.";
    };

    bonsai = lib.mkOption {
      type = lib.types.submodule bonsaiSettings;
      default = { };
      description = "Bonsai installer/runtime configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bonsai.package = bonsaiPackage;
    programs.bonsai.winePackage = winePackage;

    home.packages =
      [ bonsaiPackage ]
      ++ lib.optional (cfg.installWine && !cfg.bonsai.bundleWine) winePackage;
  };
}
