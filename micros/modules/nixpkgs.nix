{
  nixpkgs.overlays = [
    (_final: prev: {
      utillinux = prev.utillinux.override {
        systemd = null;
        systemdSupport = false;
      };

      dhcpcd = prev.dhcpcd.override {udev = null;};

      plymouth = prev.plymouth.override {
        udev = null;
        gtk3 = null;
        systemd = null;
      };

      linux_rpixxx = prev.linux_rpi.override {
        extraConfig = ''
          DEBUG_LL y
          EARLY_PRINTK y
          DEBUG_BCM2708_UART0 y
          ARM_APPENDED_DTB n
          ARM_ATAG_DTB_COMPAT n
          ARCH_BCM2709 y
          BCM2708_GPIO y
          BCM2708_NOL2CACHE y
          BCM2708_SPIDEV y
        '';
      };
    })
  ];
}
