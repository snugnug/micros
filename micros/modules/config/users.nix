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
        password = lib.mkDefault "!";
        home = "/root";
      };
    };

    micros.services = {
      user-init = {
        startOnBoot = true;
        type = "oneshot";
        startScript = ''
          #!${pkgs.busybox}/bin/ash
          # Make home directories
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "mkdir -p ${value.home}") config.users))}
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "chown ${toString value.uid}:${toString value.gid} -f -R ${value.home}") config.users))}
        '';
      };
    };

    environment.etc = mkMerge [
      {
        passwd = {
          text = lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "${name}:${
            if value.password == ""
            then ""
            else "x"
          }:${toString value.uid}:${toString value.gid}::${value.home}:${value.shell}")
          config.users));
          mode = "0644";
          uid = 0;
          gid = 0;
        };
        shadow = {
          text = lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "${name}:${value.password}:::::::") config.users));
          mode = "0640";
          uid = 0;
          gid = 0;
        };
        "login.defs" = {
          text = ''
            DEFAULT_HOME yes
            ENCRYPT_METHOD YESCRYPT
            GID_MAX 29999
            GID_MIN 1000
            SYS_GID_MAX 999
            SYS_GID_MIN 400
            SYS_UID_MAX 999
            SYS_UID_MIN 400
            UID_MAX 29999
            UID_MIN 1000
            UMASK 077
          '';
        };
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
