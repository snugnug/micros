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

      # Poweroff
      (pkgs.writeShellScriptBin "poweroff" ''
        exec runit-init 0
      '')

      # Reboot
      (pkgs.writeShellScriptBin "reboot" ''
        exec runit-init 6
      '')
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
          #!${pkgs.runtimeShell}
          PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin

          # If /etc/ssh is missing, create it.
          [ ! -d /etc/ssh ] && mkdir -p /etc/ssh

          ${optionalString config.not-os.simpleStaticIp.enable ''
            # Assign a static IP to a given interface with a set IP, route and gateway.
            ip addr add ${cfg.simpleStaticIp.address} dev ${cfg.simpleStaticIp.interface}
            ip link set ${cfg.simpleStaticIp.interface} up
            ip route add ${cfg.simpleStaticIp.route} dev ${cfg.simpleStaticIp.interface}
            ip route add default via ${cfg.simpleStaticIp.gateway} dev ${cfg.simpleStaticIp.interface}
          ''}

          # Link /bin/sh from environment.binsh, defaults to ash from buxybox.
          mkdir /bin
          ln -s ${config.environment.binsh} /bin/sh

          ${optionalString config.networking.dhcp.enable ''
            # Network discovery
            mkdir -p /var/db/dhcpcd /var/run/dhcpcd
            touch /etc/dhcpcd.conf
            ${pkgs.dhcpcd}/sbin/dhcpcd --oneshot
          ''}

          ${optionalString (config.networking.timeServers != []) ''
            # Configure timeservers
            ${pkgs.ntp}/bin/ntpdate ${toString config.networking.timeServers}
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
          #!${pkgs.runtimeShell}
          cat /proc/uptime

          # Watch the /etc/service directory for files
          # used to configure a monitored service.
          mkdir -p /etc/service

          PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin
          exec env - PATH=$PATH ${pkgs.runit}/bin/runsvdir -P /etc/service
        '';
      };

      stage-3.script = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.runtimeShell}

          echo Waiting for services to stop...
          ${pkgs.runit}/bin/sv force-stop /etc/service/*
          ${pkgs.runit}/bin/sv exit /etc/service/*

          echo Sending TERM signal to processes...
          ${pkgs.procps}/bin/pkill --inverse -s0,1 -TERM
          sleep 1

          echo Sending KILL signal to processes...
          ${pkgs.procps}/bin/pkill --inverse -s0,1 -KILL

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
