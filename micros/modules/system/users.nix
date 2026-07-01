{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption types mkMerge mkDefault mapAttrsToList;
  cfg = config.users;
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

      extraGroups = mkOption {
        type = with types; listOf str;
        default = [];
        description = "List of extra groups for the user to be added to.";
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
  groupOpts = {
    name,
    config,
    ...
  }: {
    options = {
      name = mkOption {
        type = types.passwdEntry types.str;
        description = ''
          The name of the group. If undefined, the name of the attribute set
          will be used.
        '';
      };

      gid = mkOption {
        type = with types; nullOr int;
        default = null;
        description = ''
          The group GID. If the GID is null, a free GID is picked on
          activation.
        '';
      };

      members = mkOption {
        type = with types; listOf (passwdEntry str);
        default = [];
        description = ''
          The user names of the group members, added to the
          `/etc/group` file.
        '';
      };
    };

    config = {
      name = mkDefault name;

      members = mapAttrsToList (n: u: u.name) (
        lib.filterAttrs (n: v: lib.elem name v.extraGroups) cfg
      );
    };
  };
in {
  options = {
    users = mkOption {
      default = {};
      description = ''
        Attrset of users.
      '';
      type = with types; attrsOf (submodule userOpts);
    };
    groups = mkOption {
      default = {};
      description = ''
        Attrset of groups.
      '';
      type = with types; attrsOf (submodule groupOpts);
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

          # Create users and groups with random UID/GIDs
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "useradd -m -S ${value.shell} -d ${value.home} ${value.name}") (lib.filterAttrs (name: value: value.uid == null) config.users)))}

          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "echo \"${value.name}:${value.password}\" | chpasswd -e") (lib.filterAttrs (name: value: value.uid == null) config.users)))}

          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "groupadd -U ${lib.strings.concatStringsSep "," value.members} ${value.name}") (lib.filterAttrs (name: value: value.gid == null) config.groups)))}

          # Make home directories
          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "mkdir -p ${value.home}") (lib.filterAttrs (name: value: value.uid != null) config.users)))}

          ${lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "chown ${toString value.uid}:${toString value.gid} -f -R ${value.home}") (lib.filterAttrs (name: value: value.uid != null) config.users)))}
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
          (lib.filterAttrs (name: value: value.uid != null) config.users)));
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
        group = {
          text =
            ''
              root:x:0:
              nixbld:x:30000:nixbld1,nixbld10,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9
            ''
            + lib.concatLines (builtins.attrValues (builtins.mapAttrs (name: value: "${value.name}:x:${toString value.gid}:${lib.strings.concatStringsSep "," value.members}") (lib.filterAttrs (name: value: value.gid != null) config.groups)));
          mode = "0644";
          uid = 0;
          gid = 0;
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
