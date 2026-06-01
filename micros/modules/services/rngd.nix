{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkPackageOption mkEnableOption;

  cfg = config.services.rngd;
in {
  options = {
    services.rngd = {
      enable = mkEnableOption "rngd";
      package = mkPackageOption pkgs "rng-tools" {};
    };
  };

  config = mkIf cfg.enable {
    micros.services = {
      rngd = {
        startScript = ''
          #!${pkgs.busybox}/bin/ash
          export PATH=$PATH:${lib.makeBinPath cfg.package}

          echo "Starting rngd"
          exec rngd -r /dev/hwrng
        '';
      };
    };
  };
}
