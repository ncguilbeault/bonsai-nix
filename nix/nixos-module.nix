self:
{ config, lib, ... }:

let
  cfg = config.programs.bonsai;
in
{
  imports = [
    (import ./common.nix self)
  ];

  options.programs.bonsai.installWine = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether to add the (patched) Wine package to environment.systemPackages.
      Disable if you bundle wine into the bonsai package and don't
      want a separate top-level entry.
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ lib.optional (cfg.installWine && !cfg.bonsai.bundleWine) cfg.winePackage;
  };
}
