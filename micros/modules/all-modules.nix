[
  ./config/users.nix
  ./config/system-path.nix

  ./hardware/firmware.nix

  ./security/pam.nix

  ./system/boot/runit/services.nix
  ./system/boot/runit/stages.nix
  ./system/boot/containers.nix
  ./system/boot/getty.nix
  ./system/boot/kernel.nix
  ./system/boot/stage-1.nix
  ./system/boot/stage-2.nix
  ./system/activation.nix
  ./system/build.nix
  ./system/ipxe.nix
  ./system/name.nix

  ./services/nix-daemon.nix
  ./services/getty.nix
  ./services/rngd.nix
  ./services/sshd.nix

  ./tasks/filesystems.nix

  ./virtualisation/qemu.nix

  ./environment.nix
  ./networking.nix
  ./nix.nix
  ./nixpkgs.nix
  ./nixpkgs-flake.nix
  ./systemd-compat.nix
]
