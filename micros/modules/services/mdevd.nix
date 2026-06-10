{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
in {
  options = {
    services.mdevd = {
      enable = mkEnableOption "Enable mdevd device manager" // {default = true;};
    };
  };
  config = lib.mkIf config.services.mdevd.enable {
    micros.services.mdevd = {
      startOnBoot = true;
      enable = true;
      startScript = ''
        #!${pkgs.busybox}/bin/ash

        exec ${pkgs.mdevd}/bin/mdevd
      '';
    };
    environment.etc."mdev.conf".text = ''
      -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"
      null      0:0 666
      zero      0:0 666
      full      0:0 666
      random    0:0 444
      urandom   0:0 444
      hwrandom  0:0 444

      ptmx        0:0 666
      pty.*       0:0 660
      tty         0:0 666
      tty[0-9]+   0:0 660

      vcsa[0-9]*  0:0 660
      ttyS[0-9]*  0:0 660

      snd/.*      0:0 660

      dri/.*      0:0 660
      video[0-9]+ 0:0 660
    '';
  };
}
