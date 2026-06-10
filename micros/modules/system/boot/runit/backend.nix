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

  logService = pkgs.writeScript "runit-service-logger" ''
    #!${pkgs.busybox}/bin/ash
    exec logger
  '';
  genericServices = services: (
    lib.mapAttrs (_: value: {
      inherit (value) enable name finishScript confScript;
      runScript = let
        startScriptFile = pkgs.writeScript "${value.name}-start-script" value.startScript;
      in
        if value.startScript == null
        then null
        else ''
          #!${pkgs.busybox}/bin/ash
          echo "Starting ${value.name}'s dependencies"
          ${lib.concatLines (map (x: "${pkgs.runit}/bin/sv up /etc/service/${x}") value.dependencies)}

          echo "Starting ${value.name}"
          ${startScriptFile}
          ${
            if value.type == "oneshot"
            then "exec ${pkgs.runit}/bin/sv down /etc/service/${value.name}"
            else ""
          }
        '';
    })
    services
  );

  serviceBuilder = services: (
    let
      runitServices = genericServices services;
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
          name = "service/${name}/down";
          value = {
            text = "";
            mode = "0755";
          };
        })
        runitServices)
      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/log/run";
          value = {
            source = logService;
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
  serviceDAG =
    lib.micros.dag.topoSort
    (lib.mapAttrs (_: value: (
        if value.dependencies == []
        then lib.micros.dag.entryAnywhere value
        else lib.micros.dag.entryAfter (value.dependencies) value
      ))
      config.micros.services);
  cfg = config.runit;

  bootManagerService = ''
    #!${pkgs.busybox}/bin/ash

    # Start Boot services
    echo "Starting Boot services"
    ${lib.concatLines (map (x: "${pkgs.runit}/bin/sv ${
      if x.data.type == "longrun"
      then "up"
      else "once"
    } /etc/service/${x.name}") (lib.filter (x: x.data.startOnBoot == true) serviceDAG.result))}

    # Disable this service to stop it from restarting
    exec sv down /etc/service/boot
  '';
in {
  options = {
    runit = {
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
          PATH=/run/booted-system/sw/bin

          # Link /bin/sh from environment.binsh, defaults to ash from buxybox.
          mkdir /bin
          ln -s ${config.environment.binsh} /bin/sh

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

          PATH=/run/wrappers/bin:/run/booted-system/sw/bin

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
      boot.init.availableBackends.runit = {
        name = "runit";
        executable = "${pkgs.runit}/bin/runit";
        serviceBuilder = serviceBuilder;
        requiredPackages = [runit-compat (config.runit.package)];
        supportedFeatures = ["dependencies"];
        extraFiles = {
          "runit/1".source = pkgs.writeScript "runit-stage-1" cfg.stage-1.script;
          "runit/2".source = pkgs.writeScript "runit-stage-2" cfg.stage-2.script;
          "runit/3".source = pkgs.writeScript "runit-stage-3" cfg.stage-3.script;
          "service/boot/run".source = pkgs.writeScript "boot-manager-service" bootManagerService;
        };
      };
    }
  ];
}
