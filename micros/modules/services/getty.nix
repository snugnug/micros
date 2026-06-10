{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkEnableOption types mkOption;

  cfg = config.services.getty;
in {
  options = {
    services.getty = {
      enable = mkEnableOption "getty";
      terminal = mkOption {
        type = types.str;
        default = "/dev/ttyS0";
        description = ''
          Terminal to start getty in
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    security.pam.enable = true;
    micros.services = {
      getty = {
        startOnBoot = true;
        startScript = ''
          #!${pkgs.busybox}/bin/ash
          echo "Starting getty"
          ${pkgs.busybox}/bin/busybox getty -l ${pkgs.shadow}/bin/login 0 ${cfg.terminal}
        '';
      };
    };
  };
}
