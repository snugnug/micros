[
  ./boot/containers.nix
  ./boot/kernel.nix
  ./boot/stage-1.nix
  ./boot/stage-2.nix

  ./hardware/arm32-cross-fixes.nix
  ./hardware/firmware.nix

  ./init/runit.nix
  ./services # FIXME: temporary, each service will get its own module

  ./system/activation.nix
  ./system/build.nix
  ./system/ipxe.nix

  ./base.nix
  ./environment.nix
  ./networking.nix
  ./nix.nix
  ./nixpkgs.nix
  ./nixpkgs-flake.nix
  ./qemu.nix
  ./system-path.nix
  ./systemd-compat.nix
]
