{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernelParams = ["systemConfig=${config.system.build.toplevel}"];
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
}
