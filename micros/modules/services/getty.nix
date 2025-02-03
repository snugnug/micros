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
    environment.etc = {
      "service/getty/run".source = pkgs.writeScript "start-getty" ''
        #!${pkgs.runtimeShell}
        echo "Starting getty"
        ${pkgs.busybox}/bin/busybox getty -l ${pkgs.shadow}/bin/login 0 /dev/ttyS0
      '';
    };
  };
}
