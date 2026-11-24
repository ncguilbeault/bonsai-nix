{
  description = "Bonsai-rx using Wine, packaged as Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: lib.genAttrs systems f;
      lib = nixpkgs.lib;
      # Release sets, keyed by Bonsai version. The unversioned packages track the
      # highest version.
      releases = import ./nix/releases.nix;
      releaseVersions = lib.sort lib.versionOlder (builtins.attrNames releases);
      latestVersion = lib.last releaseVersions;
      prefixName = "wine-bonsai";
      prefixPath = "$HOME/.local/share/wineprefixes";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          isArm = system == "aarch64-linux";
          # Wine has no native arm64 build on either kernel: aarch64-linux runs the
          # x86_64-linux build through FEX, aarch64-darwin runs the x86_64-darwin
          # build through Rosetta 2 (transparent, so no emulator wrapper is needed).
          winePkgs =
            if system == "aarch64-linux" then nixpkgs.legacyPackages.x86_64-linux
            else if system == "aarch64-darwin" then nixpkgs.legacyPackages.x86_64-darwin
            else pkgs;

          fex = (pkgs.fex.override { withQt = false; }).overrideAttrs (old: {
            cmakeFlags = old.cmakeFlags ++ [ "-DTUNE_CPU=none" ];
            # FEX's timed futex tests crash qemu-user, so skip tests when building via binfmt emulation
            doCheck = false;
          });

          emulator = if isArm then "${fex}/bin/FEXInterpreter" else null;

          # "11.22" -> "11_22", for use in package attribute names.
          attrKey = builtins.replaceStrings [ "." "-" "+" ] [ "_" "_" "_" ];
          shortRev = lib.substring 0 7;

          releaseList = map (v: releases.${v}) releaseVersions;
          latest = releases.${latestVersion};

          # The distinct pins of one dependency across all release sets, keyed by keyOf.
          # Two different pins under one key would make a package name ambiguous.
          uniquePins = what: keyOf: pins: lib.foldl'
            (acc: pin:
              let key = keyOf pin; in
              assert lib.assertMsg (!(acc ? ${key}) || acc.${key} == pin)
                "bonsai-nix: nix/releases.nix has two different ${what} pins for ${key}";
              acc // { ${key} = pin; })
            { }
            pins;

          winePins = uniquePins "wine" (p: p.version) (map (r: r.wine) releaseList);
          nvidiaLibsPins = uniquePins "nvidiaLibs" (p: p.version) (map (r: r.nvidiaLibs) releaseList);
          cudaRedistPins = uniquePins "cudaRedist" (p: p.version) (map (r: r.cudaRedist) releaseList);
          pythonPins = uniquePins "python" (p: p.version) (map (r: r.python) releaseList);
          gitPins = uniquePins "git" (p: p.version) (map (r: r.git) releaseList);
          nvcudaPins = uniquePins "nvcuda" (p: p.rev) (map (r: r.nvcuda) (lib.filter (r: r ? nvcuda) releaseList));

          # Every dependency is built once per pin and shared by the release sets that use it.
          # binSuffix names the Wine commands after the version (wine-11.22, winecfg-11.22, ...)
          # so that several Wine versions install side by side; the Wine build itself is the
          # same for every suffix.
          mkWine = binSuffix: pin: pkgs.callPackage ./nix/wine.nix { } {
            inherit (pin) version sha256;
            patches = pin.patches or [ ];
            stagingSrc = pkgs.fetchFromGitHub {
              owner = "wine-staging";
              repo = "wine-staging";
              rev = "v${pin.version}";
              sha256 = pin.stagingSha256;
            };
            inherit winePkgs emulator binSuffix;
          };
          wineByVersion = lib.mapAttrs (_: mkWine "") winePins;

          # nvcuda is built from source for the release sets that pin it, which allows patches
          # to be applied (e.g. the cuLaunchHostFunc callback relay, without which apps using
          # CUDA host functions such as ONNX Runtime crash). It is compiled with the oldest
          # Wine among the release sets that use the pin, so they all share one build.
          nvcudaByRev = lib.mapAttrs
            (rev: pin:
              let
                wineVersions = map (r: r.wine.version) (lib.filter (r: (r.nvcuda.rev or null) == rev) releaseList);
                buildWine = wineByVersion.${lib.head (lib.sort lib.versionOlder wineVersions)};
              in
              pkgs.callPackage ./nix/nvcuda.nix { } {
                wineTools = buildWine.passthru.wineHQ;
                inherit (pin) rev sha256;
                patches = pin.patches or [ ];
              })
            nvcudaPins;

          # A release set without an nvcuda attribute uses the nvcuda.dll bundled with nvidia-libs.
          nvidiaLibsKey = release: release.nvidiaLibs.version
            + lib.optionalString (release ? nvcuda) "-nvcuda-${shortRev release.nvcuda.rev}";
          nvidiaLibsFor = release: pkgs.callPackage ./nix/nvidia-libs.nix { } {
            inherit (nvidiaLibsPins.${release.nvidiaLibs.version}) version sha256;
            nvcuda = if release ? nvcuda then nvcudaByRev.${release.nvcuda.rev} else null;
          };

          cudaRedistByVersion = lib.mapAttrs
            (_: pin: pkgs.callPackage ./nix/cuda-redist.nix { } { inherit (pin) version components; })
            cudaRedistPins;

          pythonByVersion = lib.mapAttrs
            (_: pin: pkgs.callPackage ./nix/python.nix { } { inherit (pin) version sha256; })
            pythonPins;

          gitByVersion = lib.mapAttrs
            (_: pin: pkgs.callPackage ./nix/mingit.nix { } { inherit (pin) version sha256; })
            gitPins;

          # The Bonsai packages of one release. A pinned release names its commands after the
          # version and defaults to a prefix of its own, so it installs next to the unversioned
          # packages and other pinned releases. Wine is not put on PATH by these packages; the
          # bonsai-wine command runs Wine tools against the release's prefix.
          mkRelease = { version, pinned }:
            let
              release = releases.${version};
              nvidiaLibs = nvidiaLibsFor release;
              cudaRedist = cudaRedistByVersion.${release.cudaRedist.version};
              python = pythonByVersion.${release.python.version};
              git = gitByVersion.${release.git.version};

              mkBonsai = args: pkgs.callPackage ./nix/bonsai.nix { wine = wineByVersion.${release.wine.version}; } ({
                inherit version;
                sha256 = release.bonsai.sha256;
                prefixName = if pinned then "${prefixName}-${version}" else prefixName;
                inherit prefixPath;
                binSuffix = lib.optionalString pinned "-${version}";
                bundleWine = false;
              } // args);
            in
            {
              portable = {
                bonsai = mkBonsai { };
                bonsai-python = mkBonsai { inherit python git; };
              };
              cuda = {
                bonsai-cuda = mkBonsai { inherit nvidiaLibs cudaRedist; };
                bonsai-cuda-python = mkBonsai { inherit nvidiaLibs cudaRedist python git; };
              };
            };

          unversioned = mkRelease { version = latestVersion; pinned = false; };

          # { bonsai = ...; } -> { bonsai_2_9_1 = ...; } for every release.
          pinnedPackages = group: lib.concatMapAttrs (n: v: v) (lib.genAttrs releaseVersions (version:
            lib.mapAttrs'
              (name: value: lib.nameValuePair "${name}_${attrKey version}" value)
              (mkRelease { inherit version; pinned = true; }).${group}));

          # { "11.22" = ...; } -> { wine_11_22 = ...; }
          versioned = name: lib.mapAttrs' (key: value: lib.nameValuePair "${name}_${attrKey key}" value);
        in
        # Bonsai packages are keyed by Bonsai version; every dependency is keyed by its own
        # version, with the unversioned name tracking the highest release set.
        unversioned.portable // pinnedPackages "portable" // {
          default = unversioned.portable.bonsai;
          wine = wineByVersion.${latest.wine.version};
          python-installer = pythonByVersion.${latest.python.version};
          mingit = gitByVersion.${latest.git.version};
        }
        // versioned "wine" (lib.mapAttrs (version: mkWine "-${version}") winePins)
        // versioned "python-installer" pythonByVersion
        // versioned "mingit" gitByVersion
        # The cuda variants are x86_64-linux-only: CUDA cannot work under FEX emulation
        # (the x86_64 Wine process cannot load the host's aarch64 driver libraries), and
        # nvidia-libs dlopens the Linux NVIDIA driver, which does not exist on macOS.
        // lib.optionalAttrs (system == "x86_64-linux") (
          unversioned.cuda // pinnedPackages "cuda" // {
            nvidia-libs = nvidiaLibsFor latest;
            cuda-redist = cudaRedistByVersion.${latest.cudaRedist.version};
          }
          // lib.optionalAttrs (latest ? nvcuda) { nvcuda = nvcudaByRev.${latest.nvcuda.rev}; }
          // versioned "nvidia-libs" (lib.listToAttrs (map (r: lib.nameValuePair (nvidiaLibsKey r) (nvidiaLibsFor r)) releaseList))
          // versioned "cuda-redist" cudaRedistByVersion
          // versioned "nvcuda" (lib.mapAttrs' (rev: value: lib.nameValuePair (shortRev rev) value) nvcudaByRev)
        ));

      homeManagerModules = {
        bonsai = import ./nix/hm-module.nix self;
        default = self.homeManagerModules.bonsai;
      };

      nixosModules = {
        bonsai = import ./nix/nixos-module.nix self;
        default = self.nixosModules.bonsai;
      };
    };
}
