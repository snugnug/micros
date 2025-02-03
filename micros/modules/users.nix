{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption types mkMerge mkDefault;
  userOpts = {
    name,
    config,
    ...
  }: {
    options = {
      name = mkOption {
        type = types.str;
      };
      uid = mkOption {
        type = with types; nullOr int;
        default = null;
      };
      home = mkOption {
        type = types.path;
        default = "/var/empty";
      };
      password = mkOption {
        type = types.str;
      };
      shell = mkOption {
        type = types.nullOr (types.either types.shellPackage types.path);
        default = "/run/current-system/sw/bin/bash";
      };
    };
    config = mkMerge [
      {name = mkDefault name;}
    ];
  };
in {
  options = {
    users = mkOption {
      default = {};
      type = with types; attrsOf (submodule userOpts);
    };
  };
  config = {
    users = {
      root = {
        uid = 0;
        password = "";
      };
      micros = {
        uid = 1000;
        password = "";
      };
    };
    environment.etc = {
      passwd.text = lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: ''${name}:${value.password}:${toString value.uid}:${toString value.uid}::${value.home}:${value.shell}'') config.users));
    };
  };
}
