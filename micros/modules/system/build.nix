{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;
  inherit (config.boot.kernelPackages) kernel;
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
      image = let
        efiDir =
          pkgs.runCommand "efi-directory" {
            nativeBuildInputs = [pkgs.buildPackages.grub2_efi];
            strictDeps = true;
          } ''
            mkdir -p $out/EFI/BOOT

            # Add a marker so GRUB can find the filesystem.
            touch $out/EFI/image

            # ALWAYS required modules.
            MODULES=(
              # Basic modules for filesystems and partition schemes
              "fat"
              "iso9660"
              "part_gpt"
              "part_msdos"

              # Basic stuff
              "normal"
              "boot"
              "linux"
              "configfile"
              "loopback"
              "chain"
              "halt"

              # Allows rebooting into firmware setup interface
              "efifwsetup"

              # EFI Graphics Output Protocol
              "efi_gop"

              # User commands
              "ls"

              # System commands
              "search"
              "search_label"
              "search_fs_uuid"
              "search_fs_file"
              "echo"

              # We're not using it anymore, but we'll leave it in so it can be used
              # by user, with the console using "C"
              "serial"

              # Graphical mode stuff
              "gfxmenu"
              "gfxterm"
              "gfxterm_background"
              "gfxterm_menu"
              "test"
              "loadenv"
              "all_video"
              "videoinfo"

              # File types for graphical mode
              "png"
            )

            echo "Building GRUB with modules:"
            for mod in ''${MODULES[@]}; do
              echo " - $mod"
            done

            # Modules that may or may not be available per-platform.
            echo "Adding additional modules:"
            for mod in efi_uga; do
              if [ -f ${pkgs.grub2_efi}/lib/grub/${pkgs.grub2_efi.grubTarget}/$mod.mod ]; then
                echo " - $mod"
                MODULES+=("$mod")
              fi
            done

            # Make our own efi program, we can't rely on "grub-install" since it seems to
            # probe for devices, even with --skip-fs-probe.
            grub-mkimage \
              --directory=${pkgs.grub2_efi}/lib/grub/${pkgs.grub2_efi.grubTarget} \
              -o $out/EFI/BOOT/BOOTx64.EFI \
              -p /EFI/BOOT \
              -O ${pkgs.grub2_efi.grubTarget} \
              ''${MODULES[@]}
            cp ${pkgs.grub2_efi}/share/grub/unicode.pf2 $out/EFI/BOOT/

            cat <<EOF > $out/EFI/BOOT/grub.cfg

            set timeout=-1
            search --set=root --file /EFI/image

            insmod gfxterm
            insmod png
            set gfxpayload=keep
            set gfxmode=${lib.concatStringsSep "," [
              "1920x1200"
              "1920x1080"
              "1366x768"
              "1280x800"
              "1280x720"
              "1200x1920"
              "1024x768"
              "800x1280"
              "800x600"
              "auto"
            ]}

            if [ "\$textmode" == "false" ]; then
              terminal_output gfxterm
              terminal_input  console
            else
              terminal_output console
              terminal_input  console
              # Sets colors for console term.
              set menu_color_normal=cyan/blue
              set menu_color_highlight=white/blue
            fi

            clear
            # This message will only be viewable on the default (UEFI) console.
            echo ""
            echo "Loading graphical boot menu..."
            echo ""
            echo "Press 't' to use the text boot menu on this console..."
            echo ""


            hiddenentry 'Text mode' --hotkey 't' {
              loadfont (\$root)/EFI/BOOT/unicode.pf2
              set textmode=true
              terminal_output console
            }


            # If the parameter iso_path is set, append the findiso parameter to the kernel
            # line. We need this to allow the nixos iso to be booted from grub directly.
            if [ \''${iso_path} ] ; then
              set isoboot="findiso=\''${iso_path}"
            fi

            #
            # Menu entries
            #

            menuentry 'boot' {
              terminal_output console
              linux /boot/bzImage console=ttyS0 ${toString config.boot.kernelParams} root=LABEL=micros quiet panic=-1
              initrd /boot/initrd
            }

            menuentry 'Firmware Setup' --class settings {
              fwsetup
              clear
              echo ""
              echo "If you see this message, your EFI system doesn't support this feature."
              echo ""
            }
            menuentry 'Shutdown' --class shutdown {
              halt
            }
            EOF

            grub-script-check $out/EFI/BOOT/grub.cfg

          '';

        efiImg =
          pkgs.runCommand "efi-image_eltorito" {
            nativeBuildInputs = [pkgs.buildPackages.mtools pkgs.buildPackages.libfaketime pkgs.buildPackages.dosfstools];
            strictDeps = true;
          }
          # Be careful about determinism: du --apparent-size,
          #   dates (cp -p, touch, mcopy -m, faketime for label), IDs (mkfs.vfat -i)
          ''
            mkdir ./contents && cd ./contents
            mkdir -p ./EFI/BOOT
            cp -rp "${efiDir}"/EFI/BOOT/{grub.cfg,*.EFI,*.efi} ./EFI/BOOT

            # Rewrite dates for everything in the FS
            find . -exec touch --date=2000-01-01 {} +

            # Round up to the nearest multiple of 1MB, for more deterministic du output
            usage_size=$(( $(du -s --block-size=1M --apparent-size . | tr -cd '[:digit:]') * 1024 * 1024 ))
            # Make the image 110% as big as the files need to make up for FAT overhead
            image_size=$(( ($usage_size * 110) / 100 ))
            # Make the image fit blocks of 1M
            block_size=$((1024*1024))
            image_size=$(( ($image_size / $block_size + 1) * $block_size ))
            echo "Usage size: $usage_size"
            echo "Image size: $image_size"
            truncate --size=$image_size "$out"
            mkfs.vfat --invariant -i 12345678 -n EFIBOOT "$out"

            # Force a fixed order in mcopy for better determinism, and avoid file globbing
            for d in $(find EFI -type d | sort); do
              faketime "2000-01-01 00:00:00" mmd -i "$out" "::/$d"
            done

            for f in $(find EFI -type f | sort); do
              mcopy -pvm -i "$out" "$f" "::/$f"
            done

            # Verify the FAT partition.
            fsck.vfat -vn "$out"
          ''; # */
      in
        pkgs.callPackage (pkgs.path + "/nixos/lib/make-iso9660-image.nix") {
          contents = [
            {
              source = config.system.build.kernel + "/bzImage";
              target = "/boot/bzImage";
            }
            {
              source = config.system.build.initialRamdisk + "/initrd";
              target = "/boot/initrd";
            }
            {
              source = config.system.build.squashfs;
              target = "/root.squashfs";
            }
            {
              source = "${pkgs.syslinux}/share/syslinux";
              target = "/isolinux";
            }
            {
              source = pkgs.writeText "isolinux.cfg" ''
                SERIAL 0 115200
                TIMEOUT 35996

                DEFAULT boot

                LABEL boot
                MENU LABEL Boot Micros
                LINUX /boot/bzImage
                APPEND console=ttyS0 root=LABEL=micros init=${config.system.build.initialRamdisk}/initrd ${toString config.boot.kernelParams}
                INITRD /boot/initrd
              '';
              target = "/isolinux/isolinux.cfg";
            }
            {
              source = "${efiDir}/EFI";
              target = "/EFI";
            }
            {
              source = (pkgs.writeTextDir "grub/loopback.cfg" "source /EFI/BOOT/grub.cfg") + "/grub";
              target = "/boot/grub";
            }
            {
              source = "${efiImg}";
              target = "/boot/efi.img";
            }
          ];
          isoName = "micros-image.iso";
          volumeID = "micros";
          bootable = true;
          bootImage = "/isolinux/isolinux.bin";
          usbBootable = true;
          isohybridMbrImage = "${pkgs.syslinux}/share/syslinux/isohdpfx.bin";
          efiBootable = true;
          efiBootImage = "boot/efi.img";
          syslinux = pkgs.syslinux;
        };

      # nix-build -A system.build.toplevel && du -h $(nix-store -qR result) --max=0 -BM|sort -n
      toplevel =
        pkgs.runCommand "micros-toplevel" {
          activationScript = config.system.activationScripts.script;
        } ''
          mkdir $out

          cp ${config.system.build.bootStage2} $out/init
          substituteInPlace $out/init --subst-var-by systemConfig $out
          ln -s ${config.system.path} $out/sw
          ln -s ${kernel} $out/kernel-modules
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
