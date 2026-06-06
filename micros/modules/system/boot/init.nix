{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;

  etcSubmodule = with lib.types;
    attrsOf (
      submodule (
        {
          name,
          config,
          options,
          ...
        }: {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether this /etc file should be generated.  This
                option allows specific /etc files to be disabled.
              '';
            };

            target = lib.mkOption {
              type = lib.types.str;
              description = ''
                Name of symlink (relative to
                {file}`/etc`).  Defaults to the attribute
                name.
              '';
            };

            text = lib.mkOption {
              default = null;
              type = lib.types.nullOr lib.types.lines;
              description = "Text of the file.";
            };

            source = lib.mkOption {
              type = lib.types.path;
              description = "Path of the source file.";
            };

            mode = lib.mkOption {
              type = lib.types.str;
              default = "symlink";
              example = "0600";
              description = ''
                If set to something else than `symlink`,
                the file is copied instead of symlinked, with the given
                file mode.
              '';
            };

            uid = lib.mkOption {
              default = 0;
              type = lib.types.int;
              description = ''
                UID of created file. Only takes effect when the file is
                copied (that is, the mode is not 'symlink').
              '';
            };

            gid = lib.mkOption {
              default = 0;
              type = lib.types.int;
              description = ''
                GID of created file. Only takes effect when the file is
                copied (that is, the mode is not 'symlink').
              '';
            };

            user = lib.mkOption {
              default = "+${toString config.uid}";
              type = lib.types.str;
              description = ''
                User name of file owner.

                Only takes effect when the file is copied (that is, the
                mode is not `symlink`).

                When `services.userborn.enable`, this option has no effect.
                You have to assign a `uid` instead. Otherwise this option
                takes precedence over `uid`.
              '';
            };

            group = lib.mkOption {
              default = "+${toString config.gid}";
              type = lib.types.str;
              description = ''
                Group name of file owner.

                Only takes effect when the file is copied (that is, the
                mode is not `symlink`).

                When `services.userborn.enable`, this option has no effect.
                You have to assign a `gid` instead. Otherwise this option
                takes precedence over `gid`.
              '';
            };
          };

          config = {
            target = lib.mkDefault name;
            source = lib.mkIf (config.text != null) (
              let
                name' = "etc-" + lib.replaceStrings ["/"] ["-"] name;
              in
                lib.mkDerivedConfig options.text (pkgs.writeText name')
            );
          };
        }
      )
    );
  backendOpts = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          Name of the init backend used after stage-2 activation.
        '';
      };
      executable = mkOption {
        type = with types; either path str;
        description = ''
          Executable that stage 2 will hand off to as PID 1.
        '';
      };
      requiredPackages = mkOption {
        type = types.listOf types.package;
        description = ''
          Packages which are required for the backend to function.
        '';
      };
      serviceBuilder = mkOption {
        type = types.mkOptionType {
          name = "function";
          check = lib.isFunction;
        };
        description = ''
          Function which takes config.micros.services as an input and outputs files to be appended to environment.etc.
        '';
      };
      supportedFeatures = mkOption {
        type = types.listOf types.enum ["dependencies"];
        default = [];
        description = ''
          Extra features offered by the init backend, e.g. dependency management
        '';
      };
      extraFiles = mkOption {
        type = etcSubmodule;
        default = [];
        description = ''
          Extra files required by the init system, passed directly to environment.etc and uses the same syntax.
        '';
      };
    };
  });
in {
  options = {
    boot.init = {
      availableBackends = mkOption {
        type = types.attrsOf backendOpts;
        default = {};
        description = ''
          List of available backends.
        '';
      };
      currentBackend = mkOption {
        type = backendOpts;
        default = config.boot.init.availableBackends.runit;
        description = ''
          Init backend used after stage-2 activation has completed.
        '';
      };

      executable = mkOption {
        type = with types; either path str;
        default = config.boot.init.currentBackend.executable;
        description = ''
          Executable that stage 2 will hand off to as PID 1.
        '';
      };

      stage2Path = mkOption {
        type = types.str;
        default = "/run/booted-system/sw/bin";
        description = ''
          PATH value used by stage 2 before handing off to the init backend.
        '';
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = config.boot.init.executable;
        message = ''
          boot.init.currentBackend is set to "${config.boot.init.currentBackend.name}", but that backend does not set an executable.
        '';
      }
    ];
    environment.systemPackages = config.boot.init.currentBackend.requiredPackages;
    environment.etc = lib.mkMerge [(config.boot.init.currentBackend.serviceBuilder config.micros.services) (config.boot.init.currentBackend.extraFiles)];
  };
}
