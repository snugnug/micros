{
  config,
  lib,
  pkgs,
  ...
}: {
  options.rpi = {
    rpi1 = lib.mkEnableOption "support pi1";
    rpi2 = lib.mkEnableOption "support pi2";
    rpi3 = lib.mkEnableOption "support pi3";
    rpi4 = lib.mkEnableOption "support pi4";
    rpi5 = lib.mkEnableOption "support pi5";
    copyKernels = lib.mkOption {
      type = lib.types.separatedString "\n";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf config.rpi.rpi1 {
      rpi.copyKernels = ''
        cp ${pkgs.linuxPackages_rpi1}/zImage kernel.img
      '';
    })

    (lib.mkIf config.rpi.rpi2 {
      rpi.copyKernels = ''
        cp ${pkgs.linuxPackages_rpi2}/zImage kernel7.img
      '';
    })
  ];
}
