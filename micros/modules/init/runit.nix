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
      (pkgs.writeShellScriptBin "poweroff" ''
        exec runit-init 0
      '')

      (pkgs.writeShellScriptBin "reboot" ''
        exec runit-init 6
      '')
    ];
  };

  cfg = config.not-os;
in {
  options = {
    not-os.runit = {
      package = mkPackageOption pkgs "runit";
      stage-1 = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.runtimeShell}

          ED25519_KEY="/etc/ssh/ssh_host_ed25519_key"
          if [ ! -f $ED25519_KEY ]; then
            echo $ED25519_KEY not found. Creating it.
            ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f $ED25519_KEY -N ""
          fi

          ${optionalString cfg.simpleStaticIp.enable ''
            # Assign a static IP to a given interface with a set IP, route and gateway.
            ip addr add ${cfg.simpleStaticIp.address} dev ${cfg.simpleStaticIp.interface}
            ip link set ${cfg.simpleStaticIp.interface} up
            ip route add ${cfg.simpleStaticIp.route} dev ${cfg.simpleStaticIp.interface}
            ip route add default via ${cfg.simpleStaticIp.gateway} dev ${cfg.simpleStaticIp.interface}
          ''}

          mkdir /bin
          ln -s ${pkgs.runtimeShell} /bin/sh

          ${optionalString (config.networking.timeServers != []) ''
            ${pkgs.ntp}/bin/ntpdate ${toString config.networking.timeServers}
          ''}

          # disable DPMS on tty's
          echo -ne "\033[9;0]" > /dev/tty0

          touch /etc/runit/stopit
          chmod 0 /etc/runit/stopit
          ${
            if true
            then ""
            else "${pkgs.dhcpcd}/sbin/dhcpcd"
          }
        '';
      };

      stage-2 = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.runtimeShell}
          cat /proc/uptime

          # Watch the /etc/service directory for files
          # used to configure a monitored service.
          exec runsvdir -P /etc/service
        '';
      };

      stage-3 = mkOption {
        type = types.lines;
        default = ''
          #!${pkgs.runtimeShell}
          echo and down we go
        '';
      };
    };
  };

  config = {
    environment.systemPackages = [runit-compat];
    environment.etc = {
      "runit/1".source = pkgs.writeScript "runit-stage-1" cfg.runit.stage-1;
      "runit/2".source = pkgs.writeScript "runit-stage-2" cfg.runit.stage-2;
      "runit/3".source = pkgs.writeScript "runit-strage-3" cfg.runit.stage-3;
    };
  };
}
