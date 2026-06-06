{
  config,
  options,
  lib,
  ...
}: let
  inherit (lib) mkDefault mkEnableOption mkMerge mkOption;
  inherit (lib) types;

  serviceOpts = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      enable =
        mkEnableOption ''
          Whether to enable this service.
        ''
        // {default = true;};

      name = mkOption {
        type = types.str;
        description = ''
          Service name used by the selected init backend.
        '';
      };

      type = mkOption {
        type = types.enum ["longrun" "oneshot"];
        default = "longrun";
        description = ''
          Whether this service should be supervised continuously or run once.
        '';
      };
      dependencies = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Other services to depend on. If they are not running, start them prior to starting this service.
        '';
      };
      startOnBoot = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to start automatically after boot
        '';
      };
      earlyStartOnBoot = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to start as an early boot service directly after stage 2
        '';
      };
      startScript = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Shell script used to start the service.
        '';
      };

      finishScript = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Optional shell script run by init backends that support service exit hooks.
        '';
      };

      confScript = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Optional shell fragment available to init backends that support service configuration files.
        '';
      };
    };

    config = mkMerge [
      {name = mkDefault name;}
    ];
  });
in {
  options = {
    micros.services = mkOption {
      type = types.attrsOf serviceOpts;
      default = {};
      description = ''
        Init-backend-agnostic service definitions.
      '';
    };
  };
  config = {
    assertions =
      lib.mapAttrsToList (name: cfg: {
        assertion = !(cfg.startOnBoot && cfg.earlyStartOnBoot);
        message = "${name}: Cannot enable startOnBoot and earlyStartOnBoot at the same time.";
      })
      config.micros.services;
  };
}
