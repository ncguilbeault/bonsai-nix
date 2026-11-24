self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.bonsai;

  # Release sets keyed by Bonsai version. Version and hash defaults follow the set of
  # the configured Bonsai version, or the latest set when that version is not listed.
  releases = import "${self}/nix/releases.nix";
  latestVersion = lib.last (lib.sort lib.versionOlder (builtins.attrNames releases));
  isListed = releases ? ${cfg.bonsai.version};
  release = releases.${if isListed then cfg.bonsai.version else latestVersion};

  releaseText = attr: lib.literalExpression
    "(import ./nix/releases.nix).\${config.programs.bonsai.bonsai.version}.${attr}";

  wineSettings = {
    options = {
      version = lib.mkOption {
        type = lib.types.str;
        default = release.wine.version;
        defaultText = releaseText "wine.version";
        description = "Wine version. Used to fetch the WineHQ tarball and the matching wine-staging tag.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = release.wine.sha256;
        defaultText = releaseText "wine.sha256";
        description = "SRI hash body for the WineHQ tarball.";
      };

      stagingSha256 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = release.wine.stagingSha256 or null;
        defaultText = releaseText "wine.stagingSha256";
        description = "SRI hash of the wine-staging source tree at tag v<version>. When null, the wine-staging patches are not applied.";
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
        default = release.wine.patches or [ ];
        defaultText = releaseText "wine.patches";
        description = "Patches to apply on top of (or in place of) upstream Wine patches. Setting this replaces the release set's patches.";
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
        default = latestVersion;
        defaultText = lib.literalMD "the highest version in `nix/releases.nix`";
        description = ''
          Bonsai release version. When the version is listed in nix/releases.nix, the Wine,
          nvidia-libs, CUDA runtime and Python defaults follow that release set; otherwise
          they follow the latest release set and sha256 must be set.
        '';
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default =
          if isListed then release.bonsai.sha256
          else throw "programs.bonsai.bonsai.version: Bonsai ${cfg.bonsai.version} is not listed in nix/releases.nix; set programs.bonsai.bonsai.sha256 to the hash of its installer.";
        defaultText = releaseText "bonsai.sha256";
        description = "SRI hash body for the Bonsai installer exe. Has no default for versions not listed in nix/releases.nix.";
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

      windowsVersion = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "win10";
        example = "win10";
        description = "Windows version the prefix reports, as a winecfg version name. Set by bonsai-setup after winetricks has run; when null the version is left as it is.";
      };

      installerArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments passed to the Bonsai installer.";
      };

      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { WINEDEBUG = "-all"; };
        description = "Extra environment variables exported by bonsai, bonsai-setup and bonsai-wine.";
      };

      bundleWine = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "If true, the bonsai package symlinks the wine package into its output.";
      };
    };
  };

  nvidiaLibsSettings = {
    options = {
      enable = lib.mkEnableOption "nvidia-libs (CUDA, NVML, NVENC/NVDEC, OptiX and NvAPI support in the Wine prefix)";

      version = lib.mkOption {
        type = lib.types.str;
        default = release.nvidiaLibs.version;
        defaultText = releaseText "nvidiaLibs.version";
        description = "nvidia-libs release version.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = release.nvidiaLibs.sha256;
        defaultText = releaseText "nvidiaLibs.sha256";
        description = "SRI hash body for the nvidia-libs release tarball.";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/SveSop/nvidia-libs/releases/download";
        description = "Mirror for the nvidia-libs release tarball.";
      };
    };
  };

  cudaRedistComponent = {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Component name (e.g. cuda_cudart, libcublas, cudnn).";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Archive path relative to the mirror, as listed in NVIDIA's redist manifest.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        description = "SRI hash of the archive.";
      };
    };
  };

  cudaRuntimeSettings = {
    options = {
      enable = lib.mkEnableOption "Windows CUDA toolkit runtime DLLs (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN) in the Wine prefix";

      version = lib.mkOption {
        type = lib.types.str;
        default = release.cudaRedist.version;
        defaultText = releaseText "cudaRedist.version";
        description = "Version label for the component set.";
      };

      mirror = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Base URL for the NVIDIA redist archives. When null, the default in nix/cuda-redist.nix is used.";
      };

      components = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule cudaRedistComponent);
        default = release.cudaRedist.components;
        defaultText = releaseText "cudaRedist.components";
        description = ''
          Redist archives to fetch; the 64-bit DLLs from each are collected under x64/.
          Set to change component versions, e.g. to match a different ONNX Runtime build.
        '';
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          Package providing the runtime DLLs under x64/. When set, it is used as-is
          and version, mirror and components are ignored.
        '';
      };
    };
  };

  gitSettings = {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.python.enable;
        defaultText = lib.literalExpression "config.programs.bonsai.python.enable";
        description = "Whether to put MinGit's git.exe on the prefix's PATH, so that pip and uv in the prefix can install git+https:// dependencies.";
      };

      version = lib.mkOption {
        type = lib.types.str;
        default = release.git.version;
        defaultText = releaseText "git.version";
        description = "MinGit version, as in the archive name MinGit-<version>-64-bit.zip.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = release.git.sha256;
        defaultText = releaseText "git.sha256";
        description = "SRI hash of the MinGit-<version>-64-bit.zip archive.";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://github.com/git-for-windows/git/releases/download";
        description = "Base URL for the Git for Windows release downloads.";
      };
    };
  };

  pythonSettings = {
    options = {
      enable = lib.mkEnableOption "a python.org Windows Python install in the Wine prefix (for Bonsai.Scripting.Python)";

      version = lib.mkOption {
        type = lib.types.str;
        default = release.python.version;
        defaultText = releaseText "python.version";
        description = "Python release to install. Must have a Windows amd64 installer on python.org (patch releases past the binary cutoff of a series do not).";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = release.python.sha256;
        defaultText = releaseText "python.sha256";
        description = "SRI hash of the python-<version>-amd64.exe installer.";
      };

      mirror = lib.mkOption {
        type = lib.types.str;
        default = "https://www.python.org/ftp/python";
        description = "Base URL for the python.org release tree.";
      };

      installerArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/quiet" "InstallAllUsers=1" "PrependPath=1" "Include_test=0" "Include_launcher=0" ];
        description = "Arguments passed to the Python installer. Keep InstallAllUsers=1 and PrependPath=1 so Bonsai can find the runtime on PATH.";
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "numpy" "scipy" ];
        description = "pip requirement specifiers installed into the prefix's Python after the installer runs.";
      };
    };
  };

  hostSystem = pkgs.stdenv.hostPlatform.system;
  isArm = hostSystem == "aarch64-linux";
  # Wine has no native arm64 build on either kernel: aarch64-linux runs the x86_64-linux
  # build through FEX, aarch64-darwin runs the x86_64-darwin build through Rosetta 2.
  winePkgs =
    if hostSystem == "aarch64-linux" then self.inputs.nixpkgs.legacyPackages.x86_64-linux
    else if hostSystem == "aarch64-darwin" then self.inputs.nixpkgs.legacyPackages.x86_64-darwin
    else pkgs;
  
  fex = (pkgs.fex.override { withQt = false; }).overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [ "-DTUNE_CPU=none" ];
    # FEX's timed futex tests crash qemu-user, so skip tests when building via binfmt emulation
    doCheck = false;
  });

  emulator =
    if cfg.wine.emulator != null then cfg.wine.emulator
    else if isArm then "${fex}/bin/FEXInterpreter"
    else null;

  nvidiaLibsPackage =
    if cfg.nvidiaLibs.enable
    then pkgs.callPackage "${self}/nix/nvidia-libs.nix" { } {
      inherit (cfg.nvidiaLibs) version sha256 mirror;
    }
    else null;

  cudaRedistArgs = {
    inherit (cfg.cudaRuntime) version components;
  } // lib.optionalAttrs (cfg.cudaRuntime.mirror != null) {
    inherit (cfg.cudaRuntime) mirror;
  };

  cudaRedistPackage =
    if !cfg.cudaRuntime.enable then null
    else if cfg.cudaRuntime.package != null then cfg.cudaRuntime.package
    else pkgs.callPackage "${self}/nix/cuda-redist.nix" { } cudaRedistArgs;

  gitPackage =
    if cfg.git.enable
    then pkgs.callPackage "${self}/nix/mingit.nix" { } {
      inherit (cfg.git) version sha256 mirror;
    }
    else null;

  pythonPackage =
    if cfg.python.enable
    then pkgs.callPackage "${self}/nix/python.nix" { } {
      inherit (cfg.python) version sha256 mirror;
    }
    else null;

  wineStagingSrc =
    if cfg.wine.stagingSha256 == null then null
    else pkgs.fetchFromGitHub {
      owner = "wine-staging";
      repo = "wine-staging";
      rev = "v${cfg.wine.version}";
      sha256 = cfg.wine.stagingSha256;
    };

  wineArgs = {
    inherit (cfg.wine)
      version sha256 variant mirror patches replaceUpstreamPatches
      withWinetricks extraEnv;
    inherit (cfg) prefixName;
    prefixPath = cfg.winePrefixes;
    inherit winePkgs emulator;
    stagingSrc = wineStagingSrc;
  };

  bonsaiArgs = {
    inherit (cfg.bonsai)
      version sha256 mirror wineArch
      winetricksVerbs winetricksArgs winetricksMarkerTag windowsVersion
      installerArgs extraEnv bundleWine;
    inherit (cfg) prefixName;
    prefixPath = cfg.winePrefixes;
    nvidiaLibs = nvidiaLibsPackage;
    cudaRedist = cudaRedistPackage;
    python = pythonPackage;
    git = gitPackage;
    pythonInstallerArgs = cfg.python.installerArgs;
    pythonPackages = cfg.python.packages;
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
        commands and the wrappers of the module's Wine package (winecfg, regedit,
        etc.) so they all target the same prefix.
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

    nvidiaLibs = lib.mkOption {
      type = lib.types.submodule nvidiaLibsSettings;
      default = { };
      description = "nvidia-libs (CUDA support) configuration. Requires the proprietary NVIDIA driver on the host.";
    };

    cudaRuntime = lib.mkOption {
      type = lib.types.submodule cudaRuntimeSettings;
      default = { };
      description = "Windows CUDA toolkit runtime DLLs installed into the prefix. Only useful together with nvidiaLibs.enable.";
    };

    git = lib.mkOption {
      type = lib.types.submodule gitSettings;
      default = { };
      description = "MinGit (Git for Windows) put on the prefix's PATH by bonsai, bonsai-setup and bonsai-wine, for installing Python packages from git URLs.";
    };

    python = lib.mkOption {
      type = lib.types.submodule pythonSettings;
      default = { };
      description = "Windows Python installed into the prefix by bonsai-setup, for use with Bonsai.Scripting.Python.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bonsai.package = bonsaiPackage;
    programs.bonsai.winePackage = winePackage;
  };
}
