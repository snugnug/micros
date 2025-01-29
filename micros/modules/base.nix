{lib, ...}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) types;
in {
  options = {
    not-os.nix.enable = mkEnableOption "nix-daemon and a writeable store";

    not-os.rngd = mkEnableOption "rngd";

    not-os.simpleStaticIp = mkOption {
      type = types.bool;
      default = false;
      description = "set a static ip of 10.0.2.15";
    };
  };
}
