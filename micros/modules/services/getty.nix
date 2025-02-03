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
    runit.services = {
      getty = {
        runScript = ''
          #!${pkgs.runtimeShell}
          echo "Starting getty"
          ${pkgs.busybox}/bin/busybox getty -l ${pkgs.shadow}/bin/login 0 /dev/ttyS0
        '';
      };
    };
  };
}
