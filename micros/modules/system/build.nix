{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    system = {
      systemBuilderCommands = mkOption {
        type = types.lines;
        internal = true;
        default = "";
        description = ''
          This code will be added to the builder creating the system store path.
        '';
      };

      systemBuilderArgs = mkOption {
        type = types.attrsOf types.unspecified;
        internal = true;
        default = {};
        description = ''
          `lib.mkDerivation` attributes that will be passed to the top level system builder.
        '';
      };
    };
  };

  config = {
    boot.kernelParams = ["init=${config.system.build.initialRamdisk}/initrd"];
    system.build = {
      # TODO: this makes it so that the build closure depends on qemu no matter what.
      # We should make this optional, or even better, an imported profile.
      runvm = pkgs.writeScript "notos-vm-runner" ''
        #!${pkgs.stdenv.shell}
        exec ${pkgs.qemu_kvm}/bin/qemu-kvm -name not-os -m 512 \
          -drive index=0,id=drive1,file=${config.system.build.squashfs},readonly,media=cdrom,format=raw,if=virtio \
          -kernel ${config.system.build.kernel}/bzImage \
          -initrd ${config.system.build.initialRamdisk}/initrd -nographic \
          -append "console=ttyS0 ${toString config.boot.kernelParams} quiet panic=-1" -no-reboot \
          -net nic,model=virtio \
          -net user,net=10.0.2.0/24,host=10.0.2.2,dns=10.0.2.3,hostfwd=tcp::2222-:22 \
          -device virtio-rng-pci
      '';

      dist = pkgs.runCommand "not-os-dist" {} ''
        mkdir $out
        cp ${config.system.build.squashfs} $out/root.squashfs
        cp ${config.system.build.kernel}/*Image $out/kernel
        cp ${config.system.build.initialRamdisk}/initrd $out/initrd
        echo "${builtins.unsafeDiscardStringContext (toString config.boot.kernelParams)}" > $out/command-line
      '';

      # nix-build -A system.build.toplevel && du -h $(nix-store -qR result) --max=0 -BM|sort -n
      toplevel =
        pkgs.runCommand "not-os-toplevel" {
          activationScript = config.system.activationScripts.script;
        } ''
          mkdir $out

          cp ${config.system.build.bootStage2} $out/init
          substituteInPlace $out/init --subst-var-by systemConfig $out
          ln -s ${config.system.path} $out/sw
          echo "$activationScript" > $out/activate
          substituteInPlace $out/activate --subst-var out
          chmod u+x $out/activate

          unset activationScript
        '';

      squashfs = pkgs.callPackage (pkgs.path + "/nixos/lib/make-squashfs.nix") {
        storeContents = [config.system.build.toplevel];
      };
    };
  };
}
