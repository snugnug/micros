{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkOption mkEnableOption;
  inherit (lib) types;
in {
  options = {
    not-os.simpleStaticIp = {
      # Assign a static IP of 10.0.2.15
      enable = mkEnableOption ''
        setting a simple static IP during runit stage-1.


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
      hostName = mkOption {
        default = "micros"; # this defaults to distroId in nixpkgs, which we do not have.

        # Only allow hostnames without the domain name part (i.e. no FQDNs, see
        # e.g. "man 5 hostname") and require valid DNS labels (recommended
        # syntax). Note: We also allow underscores for compatibility/legacy
        # reasons (as undocumented feature):
        # https://github.com/NixOS/nixpkgs/pull/138978
        type =
          types.strMatching
          "^$|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$";
        description = ''
          The name of the machine. Leave it empty if you want to obtain it from a
          DHCP server (if using DHCP). The hostname must be a valid DNS label (see
          RFC 1035 section 2.3.1: "Preferred name syntax", RFC 1123 section 2.1:
          "Host Names and Numbers") and as such must not contain the domain part.
          This means that the hostname must start with a letter or digit,
          end with a letter or digit, and have as interior characters only
          letters, digits, and hyphen. The maximum length is 63 characters.
          Additionally it is recommended to only use lower-case characters.
          If (e.g. for legacy reasons) a FQDN is required as the Linux kernel
          network node hostname (uname --nodename) the option
          boot.kernel.sysctl."kernel.hostname" can be used as a workaround (but
          the 64 character limit still applies).

          WARNING: Do not use underscores (_) or you may run into unexpected issues.
        '';
      };

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

  config = {
    environment.etc.hostname = mkIf (config.networking.hostName != "") {
      text = config.networking.hostName + "\n";
    };
  };
}
