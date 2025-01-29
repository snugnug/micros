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
    services.nix-daemon = mkOption {
      enable = mkEnableOption "nix-daemon";
      package = mkPackageOption pkgs "nix";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."service/nix/run".source = pkgs.writeScript "start-nix" ''
      #!${pkgs.runtimeShell}
      ${cfg.package}/bin/nix-store --load-db < /nix/store/nix-path-registration

      echo "Starting nix-daemon"
      ${cfg.package}/bin/nix-daemon
    '';
  };
}
