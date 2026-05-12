{
  description = "Bonsai-rx using Wine, packaged as Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          wine = pkgs.callPackage ./nix/wine.nix { } { };
          bonsai = pkgs.callPackage ./nix/bonsai.nix { inherit wine; } { };
        in
        {
          inherit wine bonsai;
          default = bonsai;
        });

      homeManagerModules = {
        bonsai = import ./nix/hm-module.nix self;
        default = self.homeManagerModules.bonsai;
      };
    };
}
