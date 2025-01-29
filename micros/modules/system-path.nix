{
  config,
  lib,
  pkgs,
  ...
}:
# based heavily on https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/system-path.nix
#  crosser = if pkgs.stdenv ? cross then (x: if x ? crossDrv then x.crossDrv else x) else (x: x);
let
  inherit (lib) mkOption literalExpression;
  inherit (lib) types;

  requiredPackages = map (pkg: lib.setPrio ((pkg.meta.priority or lib.meta.defaultPriority) + 3) pkg) [
    pkgs.util-linux
    pkgs.coreutils
    pkgs.iproute2
    pkgs.iputils
    pkgs.procps
    pkgs.bashInteractive
  ];
in {
  options = {
    system.path = mkOption {
      internal = true;
    };

    environment = {
      systemPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        example = literalExpression "[ pkgs.firefox pkgs.thunderbird ]";
        description = ''
          The set of packages that appear in {file}`/run/current-system/sw`.

          These packages are automatically available to all users, and are automatically
          updated every time you rebuild the system configuration.  (The latter is the
          main difference with installing them in the default profile, {file}`/nix/var/nix/profiles/default`.
        '';
      };

      pathsToLink = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/"];
        description = "List of directories to be symlinked in {file}`/run/current-system/sw`";
      };

      extraOutputsToInstall = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["doc" "info" "docdev"];
        description = "List of additional package outputs to be symlinked into {file}`/run/current-system/sw`.";
      };

      extraSetup = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Shell fragments to be run after the system environment has been created.

          This should only be used for things that need to modify the internals of
          the environment, e.g. generating MIME caches. The environment being built
          can be accessed at `$out`.
        '';
      };
    };
  };

  config = {
    environment.systemPackages = requiredPackages;
    environment.pathsToLink = ["/bin"];
    system.path = pkgs.buildEnv {
      name = "system-path";
      paths = config.environment.systemPackages;
      inherit (config.environment) pathsToLink extraOutputsToInstall;
      postBuild = ''
        # Remove wrapped binaries, they shouldn't be accessible via PATH.
        find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete

        ${config.environment.extraSetup}
      '';
    };
  };
}
