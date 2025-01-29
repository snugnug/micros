{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkPackageOption mkEnableOption;

  sshd_config = pkgs.writeText "sshd_config" ''
    HostKey /etc/ssh/ssh_host_ed25519_key
    Port 22
    PidFile /run/sshd.pid
    Protocol 2
    PermitRootLogin yes
    PasswordAuthentication yes
    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
  '';

  cfg = config.services.sshd;
in {
  options = {
    services.sshd = mkOption {
      enable = mkEnableOption "sshd";
      package = mkPackageOption pkgs "sshd";
    };
  };

  config = {
    environment.etc."service/sshd/run".source = pkgs.writeScript "start-sshd" ''
      #!${pkgs.runtimeShell}

      echo "Starting sshd"
      ${cfg.package}/bin/sshd -f ${sshd_config}
    '';
  };
}
