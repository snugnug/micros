{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkEnableOption;

  cfg = config.services.getty;
in {
  options = {
    services.getty = {
      enable = mkEnableOption "getty";
    };
  };

  config = mkIf cfg.enable {
    security.pam.enable = true;
    micros.services = {
      getty = {
        startScript = ''
          #!${pkgs.busybox}/bin/ash
          echo "Starting getty"
          ${pkgs.busybox}/bin/busybox getty -l ${pkgs.shadow}/bin/login 0 /dev/ttyS0
        '';
      };
    };
  };
}
