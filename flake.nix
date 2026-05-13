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
      wineVersion = "11.0";
      prefixName = "wine-bonsai";
      prefixPath = "$HOME/.local/share/wineprefixes";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          wine = pkgs.callPackage ./nix/wine.nix { } {
            version = wineVersion;
            prefixName = prefixName;
            prefixPath = prefixPath;
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
