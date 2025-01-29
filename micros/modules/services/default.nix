{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkMerge;

  sshd_config = pkgs.writeText "sshd_config" ''
    HostKey /etc/ssh/ssh_host_ed25519_key
    Port 22
    PidFile /run/sshd.pid
    Protocol 2
    PermitRootLogin yes
    PasswordAuthentication yes
    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
  '';
in {
  # TODO: abstract this into a services module that automatically links services
  # into /etc/services/<name>/run without this interpolation abomination.
  environment.etc = mkMerge [
    {
      "service/sshd/run".source = pkgs.writeScript "start-sshd" ''
        #!${pkgs.runtimeShell}

        echo "Starting sshd"
        ${pkgs.openssh}/bin/sshd -f ${sshd_config}
      '';

      "service/nix/run".source = pkgs.writeScript "start-nix" ''
        #!${pkgs.runtimeShell}
        nix-store --load-db < /nix/store/nix-path-registration

        echo "Starting nix-daemon"
        nix-daemon
      '';
    }

    (mkIf config.not-os.rngd.enable {
      "service/rngd/run".source = pkgs.writeScript "start-rngd" ''
        #!${pkgs.runtimeShell}
        export PATH=$PATH:${pkgs.rng-tools}/bin

        echo "Starting rngd"
        exec rngd -r /dev/hwrng
      '';
    })
  ];
}
