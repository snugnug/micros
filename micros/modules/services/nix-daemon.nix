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
    services.nix-daemon = {
      enable = mkEnableOption "nix-daemon";
      package = mkPackageOption pkgs "nix" {};
    };
  };

  config = mkIf cfg.enable {
    environment.etc = {
      "service/nix/run".source = pkgs.writeScript "start-nix" ''
        #!${pkgs.runtimeShell}

        echo "Starting nix-daemon"
        ${cfg.package}/bin/nix-daemon
      '';

      profile.text = lib.mkAfter ''
        export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
        export CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
      '';

      "ssl/certs/ca-certificates.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      "ssl/certs/ca-bundle.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
  };
}
