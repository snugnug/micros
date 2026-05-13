{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkPackageOption;
  inherit (lib) optionalString;
  inherit (lib) types;

  runit-compat = pkgs.symlinkJoin {
    name = "runit-compat";
    paths = [
      # Join runit with some additional utility scripts
      pkgs.runit
      (pkgs.writeTextFile {
        name = "poweroff";
        executable = true;
        destination = "/bin/poweroff";
        text = ''
          #!${pkgs.busybox}/bin/ash
          exec runit-init 0
        '';
      })
      (pkgs.writeTextFile {
        name = "reboot";
        executable = true;
        destination = "/bin/reboot";
        text = ''
          #!${pkgs.busybox}/bin/ash
          exec runit-init 6
        '';
      })
    ];
  };

  cfg = config.runit;
in {
  options = {
    runit = {
      package = mkPackageOption pkgs "runit";
      stage-1.script = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.busybox}/bin/ash
          PATH=/run/booted-system/sw/bin:/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin

          # If /etc/ssh is missing, create it.
          [ ! -d /etc/ssh ] && mkdir -p /etc/ssh

          # Link /bin/sh from environment.binsh, defaults to ash from buxybox.
          mkdir /bin
          ln -s ${config.environment.binsh} /bin/sh

          # Bring network interfaces up
          ${
            if (config.boot.isContainer == false)
            then "ifup -v -a -E ${(pkgs.ifupdown-ng-minimal)}/usr/libexec/ifupdown-ng"
            else ""
          }

          ${optionalString (config.networking.timeServers != [] && config.boot.isContainer == false) ''
            # Configure timeservers
            ${pkgs.chrony}/bin/chronyd -q ${lib.concatMapStrings (x: "'server ${x} iburst '") config.networking.timeServers}
          ''}

          # disable DPMS on tty's
          echo -ne "\033[9;0]" > /dev/tty0

          touch /etc/runit/stopit
          chmod 0 /etc/runit/stopit
        '';
      };

      stage-2.script = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.busybox}/bin/ash
          cat /proc/uptime

          # Watch the /etc/service directory for files
          # used to configure a monitored service.
          mkdir -p /etc/service

          PATH=/run/booted-system/sw/bin:/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin
          exec env - PATH=$PATH ${pkgs.runit}/bin/runsvdir -P /etc/service
        '';
      };

      stage-3.script = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.busybox}/bin/ash

          echo Waiting for services to stop...
          ${pkgs.runit}/bin/sv force-stop /etc/service/*
          ${pkgs.runit}/bin/sv exit /etc/service/*

          echo Sending TERM signal to processes...
          ${pkgs.busybox}/bin/pkill -TERM -v -s 0,1
          sleep 1

          echo Sending KILL signal to processes...
          ${pkgs.busybox}/bin/pkill -KILL -v -s 0,1

          echo Unmounting filesystems, disabling swap...
          swapoff -a
          umount -r -a -t nosysfs,noproc,nodevtmpfs,notmpfs

          echo Remounting rootfs read-only...
          mount -o remount,ro /
          sync
        '';
      };
    };
  };

  config = {
    environment.systemPackages = [runit-compat];
    environment.etc = {
      # Runit has three stages: booting, running and shutdown in runit/ 1,2 and 3 respectively.
      # We create each stage manually and link them here.
      "runit/1".source = pkgs.writeScript "runit-stage-1" cfg.stage-1.script;
      "runit/2".source = pkgs.writeScript "runit-stage-2" cfg.stage-2.script;
      "runit/3".source = pkgs.writeScript "runit-stage-3" cfg.stage-3.script;
    };
  };
}
