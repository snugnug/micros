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

      # Copy Runit
      for BIN in ${pkgs.runit}/bin/*; do
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

  shell = "${extraUtils}/bin/ash";

  dhcpHook = pkgs.writeScript "dhcpHook" ''
    #!${shell}
  '';

  bootStage1 = pkgs.replaceVarsWith {
    src = ./stage-1-init.sh;
    isExecutable = true;

    replacements = {
      shell = "${extraUtils}/bin/ash";

      mountScript = ''
        ${config.not-os.preMount}
        if [ $realroot = tmpfs ]; then
          mount -t tmpfs root /mnt/ -o size=1G || exec ${shell}
        else
          mount $realroot /mnt || exec ${shell}
        fi
        chmod 755 /mnt/
        ${config.not-os.postMount}
      '';

      storeMountScript =
        if config.nix.enable
        then ''
          # make the store writeable
          mkdir -p /mnt/nix/.ro-store /mnt/nix/.overlay-store /mnt/nix/store
          mount $root /mnt/nix/.ro-store -t squashfs
          if [ $realroot = $1 ]; then
            mount tmpfs -t tmpfs /mnt/nix/.overlay-store -o size=1G
          fi
          mkdir -pv /mnt/nix/.overlay-store/work /mnt/nix/.overlay-store/rw
          modprobe overlay
          mount -t overlay overlay -o lowerdir=/mnt/nix/.ro-store,upperdir=/mnt/nix/.overlay-store/rw,workdir=/mnt/nix/.overlay-store/work /mnt/nix/store
        ''
        else ''
          # readonly store
          mount $root /mnt/nix/store/ -t squashfs
        '';

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
