{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkOption mkPackageOption mkEnableOption;

  cfg = config.services.nix-daemon;
in {
  options = {
    services.rngd = {
      enable = mkEnableOption "rngd";
      package = mkPackageOption pkgs "rng-tools" {};
    };
  };

  config = mkIf cfg.enable {
    runit.services = {
      rngd = {
        runScript = ''
          #!${pkgs.runtimeShell}
          export PATH=$PATH:${lib.makeBinPath cfg.package}

          echo "Starting rngd"
          exec rngd -r /dev/hwrng
        '';
      };
    };
  };
}
