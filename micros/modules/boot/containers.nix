{lib, ...}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    boot.isContainer = mkOption {
      type = types.bool;
      default = false;
    };
  };
}
