{lib, ...}: let
  inherit (lib) mkOption;
in {
  options = {
    # TODO, it just silently ignores all systemd services
    systemd.services = mkOption {};
    systemd.user = mkOption {};
    systemd.tmpfiles = mkOption {};
  };
}
