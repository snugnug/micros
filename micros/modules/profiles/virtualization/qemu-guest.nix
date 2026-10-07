{
  boot.initrd.kernelModules = ["virtio" "virtio_pci" "virtio_net" "virtio_rng" "virtio_blk" "virtio_console" "af_packet"];
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    neededForBoot = true;
  };
  fileSystems."/nix/store" = {
    device = "/dev/vda";
    fsType = "squashfs";
    options = ["ro"];
    neededForBoot = true;
  };
  services.getty.enable = true;
  networking.interfaces = [
    {
      name = "eth0";
    }
  ];
}
