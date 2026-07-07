{
  description = "Bonsai-rx using Wine, packaged as Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      bonsaiVersion = "2.9.1";
      wineVersion = "11.12";
      wineStagingSha256 = "sha256-3pE/RVUvH56z9Ilumokl7nNMrhfksuUWzKq6k8behW4=";
      wineSha256 = "sha256-07wJEZLZhYRsnyAGXMgfITMfAeIrc2sTHjRJ4TBmcbw=";
      bonsaiSha256 = "sha256-d3b5oOZTiLlDgLPLlMHJyXdqBvuN+6WlcYDnVpS08NI=";
      prefixName = "wine-bonsai";
      prefixPath = "$HOME/.local/share/wineprefixes";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          isArm = system == "aarch64-linux";
          winePkgs = if isArm then nixpkgs.legacyPackages.x86_64-linux else pkgs;
          
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

          wine = pkgs.callPackage ./nix/wine.nix { } {
            version = wineVersion;
            sha256 = wineSha256;
            prefixName = prefixName;
            prefixPath = prefixPath;
            stagingSrc = wineStagingSrc;
            winePkgs = winePkgs;
            emulator = if isArm then "${fex}/bin/FEXInterpreter" else null;
          };

          bonsai = pkgs.callPackage ./nix/bonsai.nix { wine = wine; } {
            version = bonsaiVersion;
            sha256 = bonsaiSha256;
            prefixName = prefixName;
            prefixPath = prefixPath;
          };
        in
        {
          inherit wine bonsai;
          default = bonsai;
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
