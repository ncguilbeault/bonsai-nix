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
        default = "sha256-wHpoV5M8H8YN/1RI1585ySSBwenbWqYo250DWERuBwE=";
        description = "SRI hash body for the WineHQ tarball.";
      };

      variant = lib.mkOption {
        type = lib.types.enum [ "full" "waylandFull" ];
        default = "full";
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

      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables exported by the wine wrapper.";
      };

      emulator = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Command that runs the x86_64 wine binaries on non-x86 hosts. Defaults to FEX's FEXInterpreter on aarch64.";
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
        default = "sha256-jL7m+I54h/f6mfEBooYze3TYp8aXofgQ1z0uB9GTmzs=";
        description = "SRI hash body for the Bonsai installer exe.";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/bonsai-rx/bonsai/releases/download";
        description = "Mirror for the Bonsai installer.";
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

  isArm = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
  winePkgs = if isArm then self.inputs.nixpkgs.legacyPackages.x86_64-linux else pkgs;
  emulator =
    if cfg.wine.emulator != null then cfg.wine.emulator
    else if isArm then "${pkgs.fex.override { withQt = false; }}/bin/FEXInterpreter"
    else null;

  wineArgs = {
    inherit (cfg.wine)
      version sha256 variant mirror patches replaceUpstreamPatches
      withWinetricks extraEnv;
    inherit (cfg) prefixName;
    prefixPath = cfg.winePrefixes;
    inherit winePkgs emulator;
  };

  bonsaiArgs = {
    inherit (cfg.bonsai)
      version sha256 mirror wineArch
      winetricksVerbs winetricksArgs winetricksMarkerTag
      installerArgs extraEnv bundleWine;
    inherit (cfg) prefixName;
    prefixPath = cfg.winePrefixes;
  };

  winePackage = pkgs.callPackage "${self}/nix/wine.nix" { } wineArgs;

  bonsaiPackage = pkgs.callPackage "${self}/nix/bonsai.nix" {
    wine = winePackage;
  } bonsaiArgs;
in
{
  options.programs.bonsai = {
    enable = lib.mkEnableOption "Bonsai-rx via patched Wine";

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

    prefixName = lib.mkOption {
      type = lib.types.str;
      default = "bonsai";
      description = ''
        Wine prefix directory name (under winePrefixes). Shared by the bonsai
        launcher and every wine wrapper (winecfg, regedit, etc.) so they all
        target the same prefix.
      '';
    };

    winePrefixes = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/wineprefixes";
      description = "Directory holding Wine prefixes. The prefix path is winePrefixes/prefixName.";
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
  };
}
