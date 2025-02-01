{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption literalMD;
  inherit (lib) optionalString;
  inherit (lib) types;

  kernel-name = config.boot.kernelPackages.kernel.name or "kernel";

  # Determine the set of modules that we need to mount the root FS.
  modulesClosure = pkgs.makeModulesClosure {
    kernel = config.system.build.kernel;
    firmware = config.hardware.firmware;
    rootModules = config.boot.initrd.availableKernelModules ++ config.boot.initrd.kernelModules;
    allowMissing = false;
  };

  # The initrd only has to mount `/` or any FS marked as necessary for
  # booting (such as the FS containing `/nix/store`, or an FS needed for
  # mounting `/`, like `/` on a loopback).
  # Check whenever fileSystem is needed for boot.  NOTE: Make sure
  # pathsNeededForBoot is closed under the parent relationship, i.e. if /a/b/c
  # is in the list, put /a and /a/b in as well.
  pathsNeededForBoot = [
    "/"
    "/nix"
    "/nix/store"
    "/var"
    "/var/log"
    "/var/lib"
    "/var/lib/nixos"
    "/etc"
    "/usr"
  ];

  fsNeededForBoot = fs: fs.neededForBoot || lib.elem fs.mountPoint pathsNeededForBoot;
  fileSystems = lib.filter fsNeededForBoot config.system.build.fileSystems;

  # A utility for enumerating the shared-library dependencies of a program
  findLibs = pkgs.buildPackages.writeShellScriptBin "find-libs" ''
    set -euo pipefail

    declare -A seen
    left=()

    patchelf="${pkgs.buildPackages.patchelf}/bin/patchelf"

    function add_needed {
      rpath="$($patchelf --print-rpath $1)"
      dir="$(dirname $1)"
      for lib in $($patchelf --print-needed $1); do
        left+=("$lib" "$rpath" "$dir")
      done
    }

    add_needed "$1"

    while [ ''${#left[@]} -ne 0 ]; do
      next=''${left[0]}
      rpath=''${left[1]}
      ORIGIN=''${left[2]}
      left=("''${left[@]:3}")
      if [ -z ''${seen[$next]+x} ]; then
        seen[$next]=1

        # Ignore the dynamic linker which for some reason appears as a DT_NEEDED of glibc but isn't in glibc's RPATH.
        case "$next" in
          ld*.so.?) continue;;
        esac

        IFS=: read -ra paths <<< $rpath
        res=
        for path in "''${paths[@]}"; do
          path=$(eval "echo $path")
          if [ -f "$path/$next" ]; then
              res="$path/$next"
              echo "$res"
              add_needed "$res"
              break
          fi
        done
        if [ -z "$res" ]; then
          echo "Couldn't satisfy dependency $next" >&2
          exit 1
        fi
      fi
    done
  '';

  extraUtils =
    pkgs.runCommand "extra-utils" {
      nativeBuildInputs = with pkgs.buildPackages; [nukeReferences bintools];
      allowedReferences = ["out"];
    } ''
      set +o pipefail

      mkdir -p $out/bin $out/lib
      ln -s $out/bin $out/sbin

      copy_bin_and_libs () {
        [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
        cp -pdv $1 $out/bin
      }

      # Copy BusyBox.
      for BIN in ${pkgs.busybox}/{s,}bin/*; do
        copy_bin_and_libs $BIN
      done

      copy_bin_and_libs ${pkgs.dhcpcd}/bin/dhcpcd

      # Copy ld manually since it isn't detected correctly
      cp -pv ${pkgs.glibc.out}/lib/ld*.so.? $out/lib

      # Copy all of the needed libraries in a consistent order so
      find $out/bin $out/lib -type f | sort | while read BIN; do
        echo "Copying libs for executable $BIN"
        for LIB in $(${findLibs}/bin/find-libs $BIN); do
          TGT="$out/lib/$(basename $LIB)"
          if [ ! -f "$TGT" ]; then
            SRC="$(readlink -e $LIB)"
            cp -pdv "$SRC" "$TGT"
          fi
        done
      done

      # Strip binaries further than normal.
      chmod -R u+w $out
      stripDirs "$STRIP" "$RANLIB" "lib bin" "-s"

      # Run patchelf to make the programs refer to the copied libraries.
      find $out/bin $out/lib -type f | while read i; do
        nuke-refs -e $out $i
      done

      find $out/bin -type f | while read i; do
        echo "patching $i..."
        patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
      done

      find $out/lib -type f \! -name 'ld*.so.?' | while read i; do
        echo "patching $i..."
        patchelf --set-rpath $out/lib $i
      done

      # Make sure that the patchelf'ed binaries still work.
      echo "testing patched programs..."
      $out/bin/ash -c 'echo hello world' | grep "hello world"

      export LD_LIBRARY_PATH=$out/lib
      $out/bin/mount --help 2>&1 | grep -q "BusyBox"
    '';

  shell = "${extraUtils}/bin/sh";

  dhcpHook = pkgs.writeScript "dhcpHook" ''
    #!${shell}
  '';

  bootStage1 = pkgs.replaceVarsWith {
    src = ./stage-1-init.sh;
    isExecutable = true;

    replacements = {
      shell = "${extraUtils}/bin/ash";

      # Expects $targetRoot to be set in the stage-1 script.
      mountScript = ''
        ${config.not-os.preMount}

        # TODO: this should be handled better
        realroot=tmpfs

        if [ "$realroot" = tmpfs ]; then
          mount -t tmpfs root "$targetRoot" -o size=1G
        else
          mount "$realroot" "$targetRoot"
        fi

        chmod 755 $targetRoot

        ${config.not-os.postMount}
      '';

      mdevRules = pkgs.writeText "mdev-conf" ''
              #
        # This is a sample mdev.conf.
        #

        # Devices:
        # Syntax: %s %d:%d %s
        # devices user:group mode

        $MODALIAS=.*	0:0	0660	@modprobe -q -b "$MODALIAS"

        # null does already exist; therefore ownership has to be changed with command
        null	0:0 0666	@chmod 666 $MDEV
        zero	0:0 0666
        full	0:0 0666

        random	0:0 0666
        urandom	0:0 0444
        hwrandom 0:0 0660

        console 0:0 0600

        # load frambuffer console when first frambuffer is found
        fb0	0:0 0660 @modprobe -q -b fbcon
        vchiq	0:0 0660

        fd0	0:0 0660
        kmem	0:0 0640
        mem	0:0 0640
        port	0:0 0640
        ptmx	0:0 0666

        # Kernel-based Virtual Machine.
        kvm		0:0 660

        # ram.*
        ram([0-9]*)	0:0 0660 >rd/%1
        loop([0-9]+)	0:0 0660 >loop/%1

        # persistent storage
        dasd.*		0:0 0660 */opt/mdev/helpers/storage-device
        mmcblk.*	0:0 0660 */opt/mdev/helpers/storage-device
        nbd.*		0:0 0660 */opt/mdev/helpers/storage-device
        nvme.*		0:0 0660 */opt/mdev/helpers/storage-device
        sd[a-z].*	0:0 0660 */opt/mdev/helpers/storage-device
        sr[0-9]+	0:0 0660 */opt/mdev/helpers/storage-device
        vd[a-z].*	0:0 0660 */opt/mdev/helpers/storage-device
        xvd[a-z].*	0:0 0660 */opt/mdev/helpers/storage-device

        md[0-9]		0:0 0660

        tty		0:0 0666
        tty[0-9]	0:0 0600
        tty[0-9][0-9]	0:0 0660
        ttyS[0-9]*	0:0 0660
        pty.*		0:0 0660
        vcs[0-9]*	0:0 0660
        vcsa[0-9]*	0:0 0660

        # rpi bluetooth
        #ttyAMA0	0:0 660 @btattach -B /dev/$MDEV -P bcm -S 115200 -N &

        ttyACM[0-9]	0:0 0660 @ln -sf $MDEV modem
        ttyUSB[0-9]	0:0 0660 @ln -sf $MDEV modem
        ttyLTM[0-9]	0:0 0660 @ln -sf $MDEV modem
        ttySHSF[0-9]	0:0 0660 @ln -sf $MDEV modem
        slamr		0:0 0660 @ln -sf $MDEV slamr0
        slusb		0:0 0660 @ln -sf $MDEV slusb0
        fuse		0:0  0666

        # dri device
        dri/.*		0:0 0660
        card[0-9]	0:0 0660 =dri/

        # alsa sound devices and audio stuff
        pcm.*		0:0 0660	=snd/
        control.*	0:0 0660	=snd/
        midi.*		0:0 0660	=snd/
        seq		0:0 0660	=snd/
        timer		0:0 0660	=snd/

        adsp		0:0 0660 >sound/
        audio		0:0 0660 >sound/
        dsp		0:0 0660 >sound/
        mixer		0:0 0660 >sound/
        sequencer.*	0:0 0660 >sound/

        SUBSYSTEM=sound;.*	0:0 0660

        # PTP devices
        ptp[0-9]	0:0 0660 */lib/mdev/ptpdev

        # virtio-ports
        SUBSYSTEM=virtio-ports;vport.* 0:0 0600 @mkdir -p virtio-ports; ln -sf ../$MDEV virtio-ports/$(cat /sys/class/virtio-ports/$MDEV/name)

        # misc stuff
        agpgart		0:0 0660  >misc/
        psaux		0:0 0660  >misc/
        rtc		0:0 0664  >misc/

        # input stuff
        SUBSYSTEM=input;.*  0:0 0660

        # v4l stuff
        vbi[0-9]	0:0 0660 >v4l/
        0[0-9]+	0:0 0660 >v4l/

        # dvb stuff
        dvb.*		0:0 0660 */lib/mdev/dvbdev

        # load drivers for usb devices
        usb[0-9]+	0:0 0660 */lib/mdev/usbdev

        # net devices
        # 666 is fine: https://www.kernel.org/doc/Documentation/networking/tuntap.txt
        net/tun[0-9]*	0:0 0666
        net/tap[0-9]*	0:0 0666

        # zaptel devices
        zap(.*)		0:0 0660 =zap/%1
        dahdi!(.*)	0:0 0660 =dahdi/%1
        dahdi/(.*)	0:0 0660 =dahdi/%1

        # raid controllers
        cciss!(.*)	0:0 0660 =cciss/%1
        cciss/(.*)	0:0 0660 =cciss/%1
        ida!(.*)	0:0 0660 =ida/%1
        ida/(.*)	0:0 0660 =ida/%1
        rd!(.*)		0:0 0660 =rd/%1
        rd/(.*)		0:0 0660 =rd/%1

        # tape devices
        nst[0-9]+.*	0:0 0660
        st[0-9]+.*	0:0 0660

        # fallback for any!device -> any/device
        (.*)!(.*)	0:0 0660 =%1/%2

      '';

      mdevHelper = pkgs.writeText "mdev-helper" ''
        #!/bin/sh

        symlink_action() {
        	case "$ACTION" in
        		add) ln -sf "$1" "$2";;
        		remove) rm -f "$2";;
        	esac
        }

        sanitise_file() {
        	sed -E -e 's/^\s+//' -e 's/\s+$//' -e 's/ /_/g' "$@" 2>/dev/null
        }

        sanitise_string() {
        	echo "$@" | sanitise_file
        }

        blkid_encode_string() {
        	# Rewrites string similar to libblk's blkid_encode_string
        	# function which is used by udev/eudev.
        	echo "$@" | sed -e 's| |\\x20|g'
        }

        : ''${SYSFS:=/sys}

        # cdrom symlink
        case "$MDEV" in
        	sr*|xvd*)
        		caps="$(cat $SYSFS/block/$MDEV/capability 2>/dev/null)"
        		if [ $(( 0x''${caps:-0} & 8 )) -gt 0 ]; then
        			symlink_action $MDEV cdrom
        		fi
        esac


        # /dev/block symlinks
        mkdir -p block
        if [ -f "$SYSFS/class/block/$MDEV/dev" ]; then
        	maj_min=$(sanitise_file "$SYSFS/class/block/$MDEV/dev")
        	symlink_action ../$MDEV block/''${maj_min}
        fi


        # by-id symlinks
        mkdir -p disk/by-id

        if [ -f "$SYSFS/class/block/$MDEV/partition" ]; then
        	# This is a partition of a device, find out its parent device
        	_parent_dev="$(basename $(''${SBINDIR:-/usr/bin}/readlink -f "$SYSFS/class/block/$MDEV/.."))"

        	partition=$(cat $SYSFS/class/block/$MDEV/partition 2>/dev/null)
        	case "$partition" in
        		[0-9]*) partsuffix="-part$partition";;
        	esac
        	# Get name, model, serial, wwid from parent device of the partition
        	_check_dev="$_parent_dev"
        else
        	_check_dev="$MDEV"
        fi

        model=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/model")
        name=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/name")
        serial=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/serial")
        wwid=$(sanitise_file "$SYSFS/class/block/$_check_dev/wwid")
        : ''${wwid:=$(sanitise_file "$SYSFS/class/block/$_check_dev/device/wwid")}

        # Sets variables LABEL, PARTLABEL, PARTUUID, TYPE, UUID depending on
        # blkid output (busybox blkid will not provide PARTLABEL or PARTUUID)
        eval $(blkid /dev/$MDEV | cut -d: -f2-)

        if [ -n "$wwid" ]; then
        	case "$MDEV" in
        		nvme*) symlink_action ../../$MDEV disk/by-id/nvme-''${wwid}''${partsuffix};;
        	esac
        	case "$wwid" in
        		naa.*) symlink_action ../../$MDEV disk/by-id/wwn-0x''${wwid#naa.};;
        	esac
        fi

        if [ -n "$serial" ]; then
        	if [ -n "$model" ]; then
        		case "$MDEV" in
        			nvme*) symlink_action ../../$MDEV disk/by-id/nvme-''${model}_''${serial}''${partsuffix};;
        			sd*) symlink_action ../../$MDEV disk/by-id/ata-''${model}_''${serial}''${partsuffix};;
        		esac
        	fi
        	if [ -n "$name" ]; then
        		case "$MDEV" in
        			mmcblk*) symlink_action ../../$MDEV disk/by-id/mmc-''${name}_''${serial}''${partsuffix};;
        		esac
        	fi

        	# virtio-blk
        	case "$MDEV" in
        		vd*) symlink_action ../../$MDEV disk/by-id/virtio-''${serial}''${partsuffix};;
        	esac
        fi

        # by-label, by-partlabel, by-partuuid, by-uuid symlinks
        if [ -n "$LABEL" ]; then
        	mkdir -p disk/by-label
        	symlink_action ../../$MDEV disk/by-label/"$(blkid_encode_string "$LABEL")"
        fi
        if [ -n "$PARTLABEL" ]; then
        	mkdir -p disk/by-partlabel
        	symlink_action ../../$MDEV disk/by-partlabel/"$(blkid_encode_string "$PARTLABEL")"
        fi
        if [ -n "$PARTUUID" ]; then
        	mkdir -p disk/by-partuuid
        	symlink_action ../../$MDEV disk/by-partuuid/"$PARTUUID"
        fi
        if [ -n "$UUID" ]; then
        	mkdir -p disk/by-uuid
        	symlink_action ../../$MDEV disk/by-uuid/"$UUID"
        fi

        # backwards compatibility with /dev/usbdisk for /dev/sd*
        if [ "''${MDEV#sd}" != "$MDEV" ]; then
        	sysdev=$(readlink $SYSFS/class/block/$MDEV)
        	case "$sysdev" in
        		*usb[0-9]*)
        			# require vfat for devices without partition
        			if ! [ -e $SYSFS/block/$MDEV ] || [ TYPE="vfat" ]; then
        				symlink_action $MDEV usbdisk
        			fi
        			;;
        	esac
        fi
      '';

      fsInfo = let
        f = fs: [
          fs.mountPoint
          (
            if fs.device != null
            then fs.device
            else "/dev/disk/by-label/${fs.label}"
          )
          fs.fsType
          (builtins.concatStringsSep "," fs.options)
        ];
      in
        pkgs.writeText "initrd-fsinfo" (lib.concatStringsSep "\n" (lib.concatMap f fileSystems));

      setHostId = optionalString (config.networking.hostId != null) ''
        hi="${config.networking.hostId}"
        ${
          if pkgs.stdenv.hostPlatform.isBigEndian
          then ''
            echo -ne "\x''${hi:0:2}\x''${hi:2:2}\x''${hi:4:2}\x''${hi:6:2}" > /etc/hostid
          ''
          else ''
            echo -ne "\x''${hi:6:2}\x''${hi:4:2}\x''${hi:2:2}\x''${hi:0:2}" > /etc/hostid
          ''
        }
      '';

      inherit extraUtils dhcpHook modulesClosure;

      inherit (config.boot.initrd) kernelModules;
      inherit (config.system.build) earlyMountScript;
    };

    postInstall = ''
      echo checking syntax
      # check both with bash
      ${pkgs.buildPackages.bash}/bin/sh -n $target
      # and with ash shell, just in case
      ${pkgs.buildPackages.busybox}/bin/ash -n $target
    '';
  };

  initialRamdisk = pkgs.makeInitrd {
    name = "initrd-${kernel-name}";

    contents = [
      {
        object = bootStage1;
        symlink = "/init";
      }
      {
        object = "${modulesClosure}/lib";
        symlink = "/lib";
      }
    ];

    inherit (config.boot.initrd) compressor compressorArgs;
  };

  netbootRamdisk = pkgs.makeInitrd {
    name = "initrd-${kernel-name}-netboot";
    prepend = ["${config.system.build.initialRamdisk}/initrd"];

    contents = [
      {
        object = config.system.build.squashfsStore;
        symlink = "/nix-store.squashfs";
      }
    ];

    inherit (config.boot.initrd) compressor compressorArgs;
  };
in {
  options = {
    not-os = {
      preMount = mkOption {
        type = types.lines;
        default = "";
      };

      postMount = mkOption {
        type = types.lines;
        default = "";
      };

      # There is no preBootCommands. Trust me, I've checked.
      postBootCommands = mkOption {
        default = "";
        example = "rm -f /var/log/messages";
        type = types.lines;
        description = ''
          Shell commands to be executed just before runit is started.
        '';
      };

      readOnlyNixStore = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If set, NixOS will enforce the immutability of the Nix store
          by making {file}`/nix/store` a read-only bind
          mount.  Nix will automatically make the store writable when
          needed.
        '';
      };
    };

    boot.initrd = {
      enable = mkEnableOption "initrd" // {default = true;};

      compressor = mkOption {
        type = with types; either str (functionTo str);
        default =
          if lib.versionAtLeast config.boot.kernelPackages.kernel.version "5.9"
          then "zstd"
          else "gzip";

        defaultText = literalMD "`zstd` if the kernel supports it (5.9+), `gzip` if not";
        description = ''
          The compressor to use on the initrd image. May be any of:

          - The name of one of the predefined compressors, see {file}`pkgs/build-support/kernel/initrd-compressor-meta.nix` for the definitions.
          - A function which, given the nixpkgs package set, returns the path to a compressor tool, e.g. `pkgs: "''${pkgs.pigz}/bin/pigz"`
          - (not recommended, because it does not work when cross-compiling) the full path to a compressor tool, e.g. `"''${pkgs.pigz}/bin/pigz"`

          The given program should read data from stdin and write it to stdout compressed.
        '';
        example = "xz";
      };

      compressorArgs = mkOption {
        default = null;
        type = types.nullOr (types.listOf types.str);
        description = "Arguments to pass to the compressor for the initrd image, or null to use the compressor's defaults.";
      };
    };
  };

  config = {
    system.build = {
      inherit bootStage1;
      inherit initialRamdisk netbootRamdisk;
      inherit extraUtils;
    };

    boot.initrd.availableKernelModules = [];
    boot.initrd.kernelModules =
      ["tun" "loop" "squashfs"]
      ++ (lib.optional config.nix.enable "overlay");
  };
}
