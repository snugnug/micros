{
  config,
  pkgs,
  lib,
  ...
}: let
  # TODO: add module options for modifying this list.
  # Probably under virtualization.* as name, memory, kernel etc.
  qemuArgs = [
    "-name micros"
    "-m 512"
    "-kernel ${config.system.build.kernel}/bzImage"
    "-initrd ${config.system.build.initialRamdisk}/initrd -nographic"
    "-drive index=0,id=drive1,file=${config.system.build.squashfs},readonly,media=cdrom,format=raw,if=virtio"
    "-append \"console=ttyS0 ${toString config.boot.kernelParams} quiet panic=-1"
    "-no-reboot"
    "-net nic,model=virtio"
    "-net user,net=10.0.2.0/24,host=10.0.2.2,dns=10.0.2.3,hostfwd=tcp::2222-:22"
    "-device virtio-rng-pci"
  ];
in {
  config.system.build.runvm = pkgs.writeShellScriptBin "micros-vm-runner" ''
    exec ${pkgs.qemu}/bin/qemu-kvm ${lib.concatStringsSep "" qemuArgs}
  '';
}

