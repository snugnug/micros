{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    boot = {
      devSize = mkOption {
        default = "5%";
        example = "32m";
        type = types.str;
      };

      devShmSize = mkOption {
        default = "50%";
        example = "256m";
        type = types.str;
      };

      runSize = mkOption {
        default = "25%";
        example = "256m";
        type = types.str;
      };
    };
  };

  config = {
    system.build.bootStage2 = pkgs.substituteAll {
      src = ./stage-2-init.sh;
      isExecutable = true;
      inherit (config.system) path;
      inherit (pkgs) runtimeShell;
    };
  };
}
