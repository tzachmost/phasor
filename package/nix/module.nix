{ self, mango }:
{ config, lib, pkgs, ... }:
let
  phasorPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ mango.nixosModules.mango ];

  programs.mango.enable = lib.mkDefault true;
  programs.mango.addLoginEntry = lib.mkDefault true;

  environment.systemPackages = [
    phasorPackage
    pkgs.quickshell
  ];

  services.displayManager.sessionPackages = [ phasorPackage ];
}
