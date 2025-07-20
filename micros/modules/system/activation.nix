{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkForce;
  inherit (lib) stringAfter;
in {
  system.activationScripts.users = ''
    # dummy to make setup-etc happy
  '';
  system.activationScripts.groups = ''
    # dummy to make setup-etc happy
  '';

  system.activationScripts.etc = stringAfter ["users" "groups"] config.system.build.etcActivationCommands;

  # Re-apply deprecated var value due to systemd preference in recent nixpkgs
  # See https://github.com/NixOS/nixpkgs/commit/59e37267556eb917146ca3110ab7c96905b9ffbd
  system.activationScripts.var = mkForce ''
    # Various log/runtime directories.
    mkdir -p /var/tmp
    chmod 1777 /var/tmp
    mkdir -p /var/lib
    chmod 1777 /var/lib
    # Empty, immutable home directory of many system accounts.
    mkdir -p /var/empty
    # Make sure it's really empty
    ${pkgs.e2fsprogs}/bin/chattr -f -i /var/empty || true
    find /var/empty -mindepth 1 -delete
    chmod 0555 /var/empty
    chown root:root /var/empty
    ${pkgs.e2fsprogs}/bin/chattr -f +i /var/empty || true
    # Link /var/run to tmpfs
    ln -sfn /run /var/run
    hostname -F /etc/hostname
  '';
}
