{
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    hardware.firmware = mkOption {
      description = ''
        Firmware packages
      '';
      type = types.listOf types.package;
      default = [];
      apply = list:
        pkgs.buildEnv {
          name = "firmware";
          paths = list;
          pathsToLink = ["/lib/firmware"];
          ignoreCollisions = true;
        };
    };
  };
}
