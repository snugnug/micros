{lib, ...}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    boot.isContainer = mkOption {
      description = ''
        Whether the image is a container.
      '';
      type = types.bool;
      default = false;
    };
  };
}
