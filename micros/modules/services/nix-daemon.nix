{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkPackageOption mkEnableOption;

  cfg = config.services.nix-daemon;
in {
  options = {
    services.nix-daemon = {
      enable = mkEnableOption "nix-daemon";
      package = mkPackageOption pkgs "nix" {};
    };
  };

  config = mkIf cfg.enable {
    micros.services = {
      nix-daemon = {
        startScript = ''
          #!${pkgs.busybox}/bin/ash

          echo "Starting nix-daemon"
          ${cfg.package}/bin/nix-daemon
        '';
      };
    };

    environment.etc = {
      profile.text = lib.mkAfter ''
        export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
        export CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
      '';
    };
  };
}
