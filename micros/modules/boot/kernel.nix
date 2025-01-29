{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernelParams = ["systemConfig=${config.system.build.toplevel}"];
  boot.kernelPackages = lib.mkDefault (
    if pkgs.system == "armv7l-linux"
    then pkgs.linuxPackages_rpi1
    else pkgs.linuxPackages
  );
}
