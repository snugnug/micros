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
        default = "";
        description = "Account Username";
      };

      uid = mkOption {
        type = with types; nullOr int;
        default = null;
        description = "Account User ID";
      };

      gid = mkOption {
        type = with types; nullOr int;
        default = config.uid;
        description = "Account group ID";
      };

      home = mkOption {
        type = types.path;
        default = "/home/${name}";
        description = "Account home directory";
      };

      password = mkOption {
        type = types.str;
        default = "!";
        description = "Hashed account password";
      };

      shell = mkOption {
        type = with types; nullOr (either shellPackage path);
        default = "/run/booted-system/sw/bin/ash";
        description = "Account login shell";
      };

      packages = mkOption {
        type = types.listOf types.package;
        default = [];
        description = "User-wide package list";
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
        password = "!";
        home = "/root";
      };
    };

    runit.services = {
      user-init = {
        runScript = ''
          #!${pkgs.busybox}/bin/ash
          # Make home directories
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "mkdir -p ${value.home}") config.users))}
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "chown ${toString value.uid}:${toString value.gid} -f -R ${value.home}") config.users))}
          exec ${pkgs.runit}/bin/sv pause /etc/service/user-init
        '';
      };
    };

    environment.etc = mkMerge [
      {
        passwd.text = lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "${name}:x:${toString value.uid}:${toString value.gid}::${value.home}:${value.shell}") config.users));
        shadow.text = lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "${name}:${value.password}:1::::::") config.users));
      }

      (lib.mapAttrs' (_: {
          packages,
          name,
          ...
        }: {
          name = "profiles/per-user/${name}";
          value.source = pkgs.buildEnv {
            name = "user-env";
            paths = packages;
          };
        })
        config.users)
    ];
  };
}
