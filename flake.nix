{
  description = "Bonsai-rx using Wine, packaged as Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      bonsaiVersion = "2.9.1";
      wineVersion = "11.12";
      nvidiaLibsVersion = "1.0.2";
      wineStagingSha256 = "sha256-3pE/RVUvH56z9Ilumokl7nNMrhfksuUWzKq6k8behW4=";
      wineSha256 = "sha256-07wJEZLZhYRsnyAGXMgfITMfAeIrc2sTHjRJ4TBmcbw=";
      bonsaiSha256 = "sha256-d3b5oOZTiLlDgLPLlMHJyXdqBvuN+6WlcYDnVpS08NI=";
      nvidiaLibsSha256 = "sha256-Aei7Y2jQiOItjo8dAklyFOjbQ2R2Ahcl7wwHB7fLFzg=";
      cudaRedistVersion = "12.8-cudnn9.25.0";
      cudaRedistComponents = [
        {
          name = "cuda_cudart";
          path = "cuda/redist/cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-12.8.90-archive.zip";
          sha256 = "sha256-SjkFj9hRlESoHPx64FXRNvSNGjH/pBriVbNbLt1h4Ts=";
        }
        {
          name = "libcublas";
          path = "cuda/redist/libcublas/windows-x86_64/libcublas-windows-x86_64-12.8.4.1-archive.zip";
          sha256 = "sha256-V6RwESzsfhEslSU93os8cYTXldvZKwved6TLf4yUyKo=";
        }
        {
          name = "libcufft";
          path = "cuda/redist/libcufft/windows-x86_64/libcufft-windows-x86_64-11.3.3.83-archive.zip";
          sha256 = "sha256-zG4LqVjPIzh7RiAXokRkxyvZAVSQRhM/PR68w9dETJA=";
        }
        {
          name = "libcurand";
          path = "cuda/redist/libcurand/windows-x86_64/libcurand-windows-x86_64-10.3.9.90-archive.zip";
          sha256 = "sha256-RuujbCB0iyGlkntWm5QzN90YSFEyEZ37OaW82k7bEuI=";
        }
        {
          name = "cuda_nvrtc";
          path = "cuda/redist/cuda_nvrtc/windows-x86_64/cuda_nvrtc-windows-x86_64-12.8.93-archive.zip";
          sha256 = "sha256-pjMCoHfwJIp0Ohp8qn29gND6xWxs+pxB+gX6ybfl7aU=";
        }
        {
          name = "cudnn";
          path = "cudnn/redist/cudnn/windows-x86_64/cudnn-windows-x86_64-9.25.0.15_cuda12-archive.zip";
          sha256 = "sha256-BulPcMUtczW37YBE7tKM6WO3/VnYwsRG/8YOaV/MrZE=";
        }
      ];
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

          wineStagingSrc = pkgs.fetchFromGitHub {
            owner = "wine-staging";
            repo = "wine-staging";
            rev = "v${wineVersion}";
            sha256 = wineStagingSha256;
          };

          # nvcuda is rebuilt from source so the cuLaunchHostFunc callback-relay patch can
          # be applied; the prebuilt release passes guest callbacks straight to the host
          # driver, which crashes any app using CUDA host functions (e.g. ONNX Runtime).
          nvcuda = pkgs.callPackage ./nix/nvcuda.nix { } {
            wineTools = wine.passthru.wineHQ;
            patches = [ ./patches/0002-nvcuda-relay-cuLaunchHostFunc-through-callback-worker.patch ];
          };

          nvidiaLibs = pkgs.callPackage ./nix/nvidia-libs.nix { } {
            version = nvidiaLibsVersion;
            sha256 = nvidiaLibsSha256;
            inherit nvcuda;
          };

          cudaRedist = pkgs.callPackage ./nix/cuda-redist.nix { } {
            version = cudaRedistVersion;
            components = cudaRedistComponents;
          };

          # Variant constructors: the wine/bonsai builds are shared across variants;
          # only the shim environment and prefix bootstrap differ.
          mkWine = { nvidiaLibs ? null }: pkgs.callPackage ./nix/wine.nix { } {
            version = wineVersion;
            sha256 = wineSha256;
            prefixName = prefixName;
            prefixPath = prefixPath;
            stagingSrc = wineStagingSrc;
            winePkgs = winePkgs;
            emulator = if isArm then "${fex}/bin/FEXInterpreter" else null;
            patches = [ ./patches/0001-Remove-assertion-line-which-causes-crash-in-Bonsai-t.patch ];
            inherit nvidiaLibs;
          };

          mkBonsai = { wine, nvidiaLibs ? null, cudaRedist ? null }: pkgs.callPackage ./nix/bonsai.nix { inherit wine; } {
            version = bonsaiVersion;
            sha256 = bonsaiSha256;
            prefixName = prefixName;
            prefixPath = prefixPath;
            inherit nvidiaLibs cudaRedist;
          };

          wine = mkWine { };
          bonsai = mkBonsai { inherit wine; };
          wineCuda = mkWine { inherit nvidiaLibs; };
          bonsaiCuda = mkBonsai { wine = wineCuda; inherit nvidiaLibs cudaRedist; };
        in
        {
          inherit wine bonsai;
          default = bonsai;
        }
        # The cuda variants are x86_64-linux-only: CUDA cannot work under FEX emulation
        # (the x86_64 Wine process cannot load the host's aarch64 driver libraries), and
        # nvidia-libs dlopens the Linux NVIDIA driver, which does not exist on macOS.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          wine-cuda = wineCuda;
          bonsai-cuda = bonsaiCuda;
          nvidia-libs = nvidiaLibs;
          nvcuda = nvcuda;
          cuda-redist = cudaRedist;
        });

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
