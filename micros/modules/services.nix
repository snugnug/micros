{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf types mkOption mkMerge mkDefault;
  serviceOpts = {
    name,
    config,
    ...
  }: {
    options = {
      name = mkOption {
        type = types.str;
      };
      runScript = mkOption {
        type = types.str;
        default = "#!${pkgs.runtimeShell}";
      };
      finishScript = mkOption {
        type = types.str;
        default = "#!${pkgs.runtimeShell}";
      };
      confScript = mkOption {
        type = types.str;
        default = "#!${pkgs.runtimeShell}";
      };
    };
    config = mkMerge [
      {name = mkDefault name;}
    ];
  };
in {
  options = {
    runitServices = mkOption {
      default = {};
      type = with types; attrsOf (submodule serviceOpts);
    };
  };
  config = {
    environment.etc = mkMerge [
      (lib.mapAttrs' (name: value: {
          name = "service/${name}/run";
          value = {
            text = ''${value.runScript}'';
            mode = "0755";
          };
        })
        config.runitServices)
      (lib.mapAttrs' (name: value: {
          name = "service/${name}/finish";

          value = {
            text = ''${value.finishScript}'';
            mode = "0755";
          };
        })
        config.runitServices)
      (lib.mapAttrs' (name: value: {
          name = "service/${name}/conf";
          value = {
            text = ''${value.confScript}'';
            mode = "0755";
          };
        })
        config.runitServices)
    ];
  };
}
