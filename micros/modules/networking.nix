{lib, ...}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    networking.timeServers = mkOption {
      type = types.listOf types.str;
      default = [
        "0.nixos.pool.ntp.org"
        "1.nixos.pool.ntp.org"
        "2.nixos.pool.ntp.org"
        "3.nixos.pool.ntp.org"
      ];
      description = ''
        The set of NTP servers from which to synchronise.
      '';
    };
  };
}
