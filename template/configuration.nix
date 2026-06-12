{
  pkgs,
  lib,
  ...
}: {
  # Enable the Getty login manager on the default terminal /dev/ttyS0
  services.getty.enable = true;

  users = {
    micros = {
      uid = 1000;
      gid = 1000;
      password = ""; # Blank password denotes passwordless login is allowed, use "!" (default) to disable password login entirely. To set a password, set this string to a hashed password using the `mkpasswd` command.
      packages = [
        pkgs.vim
        pkgs.ssh
      ]; # User-wide packages
    };
  };

  # Add a custom service
  micros.services = {
    custom-service = {
      startOnBoot = true; # Start the service with the rest of a system
      type = "oneshot"; # Do not restart the service after it stops
      startScript = ''
        #!${pkgs.busybox}/bin/ash

        exec ${pkgs.hello}
      ''; # Run a basic hello world program.
    };
  };

  environment.systemPackages = [
    pkgs.curl
  ]; # System-wide packages

  networking.firewall.enable = true;
  networking.nftables.enable = true;
}
