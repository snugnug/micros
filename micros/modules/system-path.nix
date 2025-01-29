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

  requiredPackages = with pkgs; [
    utillinux
    coreutils
    iproute2
    iputils
    procps
    bashInteractive
    runit
  ];
in {
  options = {
    environment = {
      systemPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        example = literalExpression "[ pkgs.firefox pkgs.thunderbird ]";
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
    };

    system.path = mkOption {
      internal = true;
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
        # TODO, any system level caches that need to regenerate
      '';
    };
  };
}
