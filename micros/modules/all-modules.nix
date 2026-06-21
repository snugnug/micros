[
  ./hardware/firmware.nix

  ./security/pam.nix
  ./security/wrappers.nix

  ./system/init-systems/runit/backend.nix

  ./system/boot/containers.nix
  ./system/boot/init.nix
  ./system/boot/kernel.nix
  ./system/boot/stage-1.nix
  ./system/boot/stage-2.nix

  ./system/activation/activation.nix
  ./system/activation/activation-script.nix

  ./system/environment/etc-setup.nix
  ./system/environment/environment.nix

  ./system/build.nix
  ./system/name.nix
  ./system/services.nix
  ./system/syslog.nix
  ./system/filesystems.nix
  ./system/users.nix
  ./system/system-path.nix
  ./system/systemd-compat.nix

  ./services/chronyd.nix
  ./services/nix-daemon.nix
  ./services/getty.nix
  ./services/rngd.nix
  ./services/sshd.nix
  ./services/mdevd.nix

  ./virtualisation/qemu.nix
  ./virtualisation/lxc-container.nix

  ./networking/networking.nix
  ./networking/firewall.nix
  ./networking/nftables.nix

  ./nix/nix.nix
  ./nix/nixpkgs.nix
  ./nix/nixpkgs-flake.nix
]
