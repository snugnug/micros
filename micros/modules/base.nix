{lib, ...}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) types;
in {
  options = {
    # TODO: those should be put into a dedicated services module
    # and converted into runit service executables.
    not-os.nix.enable = mkEnableOption "nix-daemon and a writeable store";

    not-os.rngd.enable = mkEnableOption "rngd";
  };
}
