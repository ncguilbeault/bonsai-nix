{
  description = "Bonsai-rx using Wine, packaged as Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      bonsaiVersion = "2.9.0";
      wineVersion = "11.8";
      wineStagingSha256 = "sha256-lW5dfCfsB+z84mlLpfmkR7QDxmhL+RcBufSftUutHto=";
      wineSha256 = "sha256-U6qFmV1Ll/ARahxWuKahQXcw71mid4GdLT0xNk6lVrA=";
      prefixName = "wine-bonsai";
      prefixPath = "$HOME/.local/share/wineprefixes";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

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
          };

          bonsai = pkgs.callPackage ./nix/bonsai.nix { wine = wine; } {
            version = bonsaiVersion;
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
