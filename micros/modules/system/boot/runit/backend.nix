{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption mkPackageOption;
  inherit (lib) mkIf mkMerge mkDefault optionalString;
  inherit (lib) mapAttrs';
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

  serviceOpts = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      enable =
        mkEnableOption ''
          Whether to enable the service. If set to `false`, then the service files
          in {file}`/etc/service` will not be created.
        ''
        // {default = true;};

      name = mkOption {
        type = types.str;
        description = ''
          Name of the service. This will determine the final path of the script
          in {file}`/etc/service`. For example, `name = "openssh"` would create
          the directory {file}`/etc/openssh` and place appropriate scripts in
          the created directory.
        '';
      };

      # TODO: those need descriptions. We should link relevant runit documentation
      # if any, and describe the process of execution. For example, can any one of
      # those options be omitted? Should be documented.
      runScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Script ran on service startup. Creates the {file}`/etc/service/<name>/run` file.
          Services are ran constantly by default. Use `sv pause <name>` in the run
          script to make the script act as a one-shot.
        '';
      };

      finishScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Script ran on service shutdown. Creates the {file}`/etc/service/<name>/finish` file.
          Can be undefined.
        '';
      };

      confScript = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Script which can be sourced by the run script to define variables.
          Not used by default, and can be undefined.
        '';
      };
    };

    config = mkMerge [
      {name = mkDefault name;}
    ];
  });

  genericServices = services: (
    lib.mapAttrs (_: value: {
      inherit (value) enable name finishScript confScript;
      runScript =
        if value.startScript == null
        then null
        else if value.type == "oneshot"
        then ''
          ${value.startScript}
          # Runit will restart an exited run script unless the service is marked down.
          exec ${pkgs.runit}/bin/sv down /etc/service/${value.name}
        ''
        else value.startScript;
    })
    services
  );

  serviceBuilder = services: (
    let
      runitServices = (genericServices services) // config.runit.services;
    in (mkMerge [
      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/run";
          value = mkIf (value.runScript != null) {
            text = ''${value.runScript}'';
            mode = "0755";
          };
        })
        runitServices)

      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/finish";

          value = mkIf (value.finishScript != null) {
            text = ''${value.finishScript}'';
            mode = "0755";
          };
        })
        runitServices)

      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/conf";
          value = mkIf (value.confScript != null) {
            text = ''${value.confScript}'';
            mode = "0755";
          };
        })
        runitServices)
    ])
  );
  cfg = config.runit;
in {
  options = {
    runit = {
      services = mkOption {
        type = types.attrsOf serviceOpts;
        default = {};
      };
      package = mkOption {
        type = types.package;
        default = pkgs.runit;
        description = ''
          Package to use as the runit executable
        '';
      };
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

  config = mkMerge [
    {
      assertions = [
        {
          assertion = config.boot.init.currentBackend == config.boot.init.availableBackends.runit || config.runit.services == {};
          message = ''
            runit.services is set, but boot.init.system is "${config.boot.init.system}".
            Use micros.services for backend-agnostic services or select the runit backend.
          '';
        }
      ];
      boot.init.availableBackends.runit = {
        name = "runit";
        executable = "${pkgs.runit}/bin/runit";
        serviceBuilder = serviceBuilder;
        requiredPackages = [runit-compat (config.runit.package)];
        extraFiles = {
          "runit/1".source = pkgs.writeScript "runit-stage-1" cfg.stage-1.script;
          "runit/2".source = pkgs.writeScript "runit-stage-2" cfg.stage-2.script;
          "runit/3".source = pkgs.writeScript "runit-stage-3" cfg.stage-3.script;
        };
      };
    }
  ];
}
