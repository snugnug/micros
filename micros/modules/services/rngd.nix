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
    environment.etc."service/rngd/run".source = pkgs.writeScript "start-rngd" ''
      #!${pkgs.runtimeShell}
      export PATH=$PATH:${lib.makeBinPath cfg.package}

      echo "Starting rngd"
      exec rngd -r /dev/hwrng
    '';
  };
}
