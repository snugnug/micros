{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) mkIf mkMerge mkDefault;
  inherit (lib) mapAttrs';
  inherit (lib) types;

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
in {
  options = {
    runit.services = mkOption {
      type = types.attrsOf serviceOpts;
      default = {};
    };
  };

  config = {
    environment.etc = mkMerge [
      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/run";
          value = mkIf (value.runScript != null) {
            text = ''${value.runScript}'';
            mode = "0755";
          };
        })
        config.runit.services)

      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/finish";

          value = mkIf (value.finishScript != null) {
            text = ''${value.finishScript}'';
            mode = "0755";
          };
        })
        config.runit.services)

      (mapAttrs' (name: value: {
          inherit (value) enable;
          name = "service/${name}/conf";
          value = mkIf (value.confScript != null) {
            text = ''${value.confScript}'';
            mode = "0755";
          };
        })
        config.runit.services)
    ];
  };
}
