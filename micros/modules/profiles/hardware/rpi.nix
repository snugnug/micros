{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) mkIf mkMerge;
  inherit (lib) types;

  cfg = config.not-os;
in {
  options.not-os = {
    rpi1 = mkEnableOption "support for pi1";
    rpi2 = mkEnableOption "support for pi2";
    rpi3 = mkEnableOption "support for pi3";
    rpi4 = mkEnableOption "support for pi4";
    rpi5 = mkEnableOption "support for pi5";
    rpi.copyKernels = mkOption {
      type = types.separatedString "\n";
    };
  };

  config = mkMerge [
    (mkIf cfg.rpi1 {
      not-os.rpi.copyKernels = ''
        cp ${pkgs.linuxPackages_rpi1.kernel}/zImage kernel.img
      '';
    })

    (mkIf cfg.rpi2 {
      not-os.rpi.copyKernels = ''
        cp ${pkgs.linuxPackages_rpi2.kernel}/zImage kernel7.img
      '';
    })

    {
      boot.kernelPackages = pkgs.linuxPackages_rpi2;
      environment.systemPackages = [pkgs.strace];

      system.build.rpi-image = let
        firm = config.system.build.rpi-firmware;

        cmdline = pkgs.writeText "cmdline.txt" ''
          console=ttyS0,115200 pi3-disable-bt kgdboc=ttyS0,115200 systemConfig=${builtins.unsafeDiscardStringContext config.system.build.toplevel} netroot=192.168.2.1=9080d9b6/root.squashfs quiet splash plymouth.ignore-serial-consoles plymouth.ignore-udev
        '';

        config_txt = pkgs.writeText "config.txt" ''
          initramfs initrd followkernel
          dtoverlay=pi3-disable-bt
          enable_uart=1
          auto_initramfs=1
          ramfsfile=initrd
        '';
      in
        pkgs.runCommand "rpi-image" {} ''
          mkdir $out
          cd $out
          cp ${config_txt} config.txt
          cp ${cmdline} cmdline.txt
          cp ${config.system.build.kernel}/*zImage kernel7.img
          cp ${config.system.build.squashfs} root.squashfs
          cp ${firm}/boot/{bcm2710-rpi-3-b.dtb,bcm2709-rpi-2-b.dtb} .
          cp -r ${firm}/boot/overlays overlays
          cp ${firm}/boot/start.elf start.elf
          cp ${firm}/boot/fixup.dat fixup.dat
          cp ${config.system.build.initialRamdisk}/initrd initrd
          ls -ltrhL
        '';

      system.build.rpi-image-tar = pkgs.runCommand "dist.tar" {} ''
        mkdir -p $out/nix-support
        tar -cvf $out/dist.tar ${config.system.build.rpi-image}
        echo "file binary-dist $out/dist.tar" >> $out/nix-support/hydra-build-products
      '';
    }
  ];
}
