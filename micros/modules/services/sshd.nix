{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkPackageOption mkEnableOption;
  inherit (lib) mkIf;
  inherit (lib) types;

  # TODO: this needs to be integrated into the systemd module as `services.sshd.settings`
  # and generated dynamically. This is neither a good solution, nor a long-term one. We
  # would like this to be modular alongside hostKeys options.
  sshd_config = pkgs.writeText "sshd_config" ''
    Port 22
    PidFile /run/sshd.pid
    Protocol 2
    PermitRootLogin yes
    PasswordAuthentication yes
    AuthorizedKeysFile ${toString cfg.authorizedKeysFiles}
    ${lib.flip lib.concatMapStrings cfg.hostKeys (k: ''
      HostKey ${k.path}
    '')}
  '';

  cfg = config.services.sshd;
in {
  options = {
    services.sshd = {
      enable = mkEnableOption "sshd";
      package = mkPackageOption pkgs "openssh" {};

      hostKeys = mkOption {
        type = with types; listOf attrs;
        default = [
          {
            type = "rsa";
            bits = 4096;
            path = "/etc/ssh/ssh_host_rsa_key";
          }
          {
            type = "ed25519";
            path = "/etc/ssh/ssh_host_ed25519_key";
          }
        ];

        description = ''
          MicrOS can automatically generate SSH host keys. This option
          specifies the path, type and size of each key. See
          {manpage}`ssh-keygen(1)` for supported types and sizes.
        '';
      };

      authorizedKeysFiles = mkOption {
        type = with types; listOf str;
        default = ["%h/.ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u"];
        description = ''
          Specify the rules for which files to read on the host.

          These are paths relative to the host root file system or home
          directories and they are subject to certain token expansion rules.
          See `AuthorizedKeysFile` in man `sshd_config` for details.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    runit.services = {
      sshd = {
        runScript = ''
          #!${pkgs.runtimeShell}

          echo "Starting sshd"
          ${cfg.package}/bin/sshd -f ${sshd_config}
        '';
      };
    };

    environment.etc = mkIf cfg.enable {
      # TODO: this should be a module option. user = {key = ...; rounds = ...; } or
      # something similar
      "ssh/authorized_keys.d/root" = {
        text = "";
        mode = "0444";
      };
    };
  };
}
