{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkPackageOption mkEnableOption;

  cfg = config.services.chronyd;
in {
  options = {
    services.chronyd = {
      enable = mkEnableOption "Enable chronyd time server" // {default = !config.boot.isContainer;};
      package = mkPackageOption pkgs "chrony" {};
    };
  };

  config = mkIf cfg.enable {
    environment.etc = {
      "chrony.conf".text = ''
        ${lib.concatMapStringsSep "\n" (x: "server ${x} iburst ") config.networking.timeServers}
      '';
    };
    micros.services = {
      chronyd = {
        startOnBoot = true;
        dependencies = ["networking"];
        startScript = ''
          #!${pkgs.busybox}/bin/ash
          export PATH=$PATH

          echo "Starting chronyd"
          exec ${cfg.package}/bin/chronyd -d
        '';
      };
    };
  };
}
