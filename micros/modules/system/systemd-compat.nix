{lib, ...}: let
  inherit (lib) mkOption;
in {
  options = {
    # TODO, it just silently ignores all systemd services
    systemd.services = mkOption {
      description = ''
      '';
    };
    systemd.user = mkOption {
      description = ''
      '';
    };
    systemd.tmpfiles = mkOption {
      description = ''
      '';
    };
  };
}
