{lib, ...}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) types;
in {
  options = {
    not-os.simpleStaticIp = {
      # a static ip of 10.0.2.15
      enable = mkEnableOption ''
        Setting a simple static IP during runit stage-1.


        The static IP will be set to the value of {option}`not-os.simpleStaticIp.address`
        therefore you must configure address, route, gateway and interface accordingly.
      '';

      address = mkOption {
        type = types.str;
        default = "10.0.2.15";
        description = "The static IP to be assigned to the machine in stage-1";
      };

      route = mkOption {
        type = types.str;
        default = "10.0.2.0/24";
        description = "The network route to be used for directing traffic.";
      };

      interface = mkOption {
        type = types.str;
        default = "eth0";
        example = "ens33";
        description = "The network interface to be used for the static IP configuration.";
      };

      gateway = mkOption {
        type = types.str;
        default = "10.0.2.2";
        description = "The IP address of the default gateway.";
      };
    };

    networking = {
      dhcp.enable = mkEnableOption "dhcp";
      timeServers = mkOption {
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
  };
}
