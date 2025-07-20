{
  pkgs,
  lib,
  ...
}: {
  # The initrd has to contain any module that might be necessary for
  # supporting the most important parts of HW like drives.
  boot.initrd.kernelModules = [
    # SATA/PATA support.
    "ahci"

    "ata_piix"

    "sata_inic162x"
    "sata_nv"
    "sata_mv"
    "sata_promise"
    "sata_qstor"
    "sata_sil"
    "sata_sil24"
    "sata_sis"
    "sata_svw"
    "sata_sx4"
    "sata_uli"
    "sata_via"
    "sata_vsc"

    "pata_ali"
    "pata_amd"
    "pata_artop"
    "pata_atiixp"
    "pata_efar"
    "pata_hpt366"
    "pata_hpt37x"
    "pata_hpt3x2n"
    "pata_hpt3x3"
    "pata_it8213"
    "pata_it821x"
    "pata_jmicron"
    "pata_marvell"
    "pata_mpiix"
    "pata_netcell"
    "pata_ns87410"
    "pata_oldpiix"
    "pata_pcmcia"
    "pata_pdc2027x"
    "pata_qdi"
    "pata_rz1000"
    "pata_serverworks"
    "pata_sil680"
    "pata_sis"
    "pata_sl82c105"
    "pata_triflex"
    "pata_via"
    "pata_winbond"

    # SCSI support (incomplete).
    "3w-9xxx"
    "3w-xxxx"
    "aic79xx"
    "aic7xxx"
    "arcmsr"
    "hpsa"

    # USB support, especially for booting from USB CD-ROM
    # drives.
    "uas"
    "uhci-hcd"
    "ohci-hcd"
    "usb-storage"
    "hid"
    "cdrom"
    "sr_mod"
    "mc"
    "iso9660"
    "isofs"
    "sg"
    "st"
    "ch"
    "scsi_common"
    "scsi_mod"
    "ufshcd-core"
    "ufshcd-pci"
    "ufshcd-pltfrm"
    "usb_f_mass_storage"
    "g_mass_storage"
    "libcomposite"
    "mv_udc"
    "gr_udc"
    "sd_mod"
    # SD cards.
    "sdhci_pci"

    # NVMe drives
    "nvme"

    # Firewire support.  Not tested.
    "ohci1394"
    "sbp2"

    # Virtio (QEMU, KVM etc.) support.
    "virtio_net"
    "virtio_pci"
    "virtio_mmio"
    "virtio_blk"
    "virtio"
    "virtio_scsi"
    "virtio_balloon"
    "virtio_console"
    "af_packet"
    # VMware support.
    "mptspi"
    "vmxnet3"
    "vsock"
  ];
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    neededForBoot = true;
  };
  fileSystems."/iso" = {
    device = "/dev/root";
    fsType = "iso9660";
    neededForBoot = true;
  };
  fileSystems."/nix/store" = {
    device = "/mnt-root/iso/root.squashfs";
    fsType = "auto";
    neededForBoot = true;
  };
  services.getty.enable = true;
  networking.interfaces = [
    {
      name = "eth0";
    }
  ];
  networking.firewall.allowedTCPPorts = [22];
  networking.firewall.enable = true;
  networking.nftables.enable = true;
  services.sshd.enable = true;
}
