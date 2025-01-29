{stdenv, ...}: let
  inherit (import <nixpkgs/nixos/lib/testing-python.nix> {inherit (stdenv) system;}) makeTest;

  baseConfig =
    (import ../micros/lib/eval-config.nix {
      modules = [./test-instrumentation.nix ../qemu.nix];
    })
    .config;
in {
  ipxeCrypto = makeTest {
    name = "ipxe-crypto";
    nodes = {};
    testScript = ''
      import time

      machine = create_machine(
          {
              "qemuFlags": "-device virtio-rng-pci -kernel ${baseConfig.system.build.ipxe}/ipxe.lkrn -m 768 -net nic,model=e1000 -net user,tftp=${baseConfig.system.build.ftpdir}/",
          }
      )
      machine.start()
      time.sleep(6)
      machine.screenshot("test1")
      machine.sleep(1)
      machine.screenshot("test2")
      machine.shutdown()
    '';
  };
  normalBoot = makeTest {
    name = "normal-boot";
    nodes = {};
    testScript = ''
      machine = create_machine(
          {
              "qemuFlags": '-device virtio-rng-pci -kernel ${baseConfig.system.build.kernel}/bzImage -initrd ${baseConfig.system.build.initialRamdisk}/initrd -append "console=tty0 console=ttyS0 ${toString baseConfig.boot.kernelParams}" -drive index=0,id=drive1,file=${baseConfig.system.build.squashfs},readonly,media=cdrom,format=raw,if=virtio',
          }
      )
      machine.start()
      machine.sleep(1)
      machine.screenshot("test")
      machine.shutdown()
    '';
  };
}
