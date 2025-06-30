{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkOption mkDefault mkMerge;
  inherit (lib) types;
  interfaceOpts = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the interface. This determines if the interface will have an entry in the /etc/network/interfaces file.
        '';
      };
      name = mkOption {
        type = types.str;
        description = ''
          Name of the interface. This is used in the /etc/network/interfaces file and needs to be set to a valid network interface, e.g. eth0, ens1p0, wlp2s0, etc.
        '';
      };
      dhcp = mkOption {
        type = types.nullOr types.bool;
        description = ''
          Whether to use DHCP for the interface. When null (default), DHCP is used if ipv4 has no manually configured addresses.
        '';
        default = null;
      };
      slaac = mkOption {
        type = types.nullOr types.bool;
        description = ''
          Whether to use SLAAC for configuring IPV6 on the interface. When null (default), SLAAC is used if ipv6 has no manually configured addresses.
        '';
        default = null;
      };
      ipv4 = {
        address = mkOption {
          type = with types; nullOr (strMatching "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\/(3[0-2]|[1-2]?\d)$");
          description = ''
            IPV4 address given to the interface, with the subnet mask. Given as "x.x.x.x/xx".
          '';
          default = null;
        };
        gateway = mkOption {
          type = with types; nullOr (strMatching "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\/(3[0-2]|[1-2]?\d)$");
          description = ''
            IPV4 address used as the network gateway. Given as "x.x.x.x/xx".
          '';
          default = null;
        };
      };
      ipv6 = {
        address = mkOption {
          type = with types; nullOr (strMatching "(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\/([1-9]|[1-9][0-9]|1[01][0-9]|12[0-8])");
          description = ''
            IPV6 address given to the interface, with the subnet mask.
          '';
          default = null;
        };
        gateway = mkOption {
          type = with types;
            nullOr (strMatching "(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))");
          description = ''
            IPV6 address used as the network gateway.
          '';
          default = null;
        };
      };
    };
  };
in {
  options = {
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
      interfaces = mkOption {
        type = with types; listOf interfaceOpts;
        description = ''
          The list of interfaces to configure. By default, all network interfaces detected on startup are brought up with DHCP. Use this to manually configure interfaces and set static IPs.
        '';
        default = [];
      };
      nameservers = mkOption {
        type = with types; listOf (strMatching "(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])");
        description = ''
          The list of nameservers used. This can be overrided by DHCP. Defaults to cloudflare DNS (1.1.1.1, 1.0.0.1).
        '';
        default = ["1.1.1.1" "1.0.0.1"];
      };
      hostId = mkOption {
        default = null;
        example = "4e98920d";
        type = types.nullOr types.str;
        description = ''
          The 32-bit host ID of the machine, formatted as 8 hexadecimal characters.

          You should try to make this ID unique among your machines. You can
          generate a random 32-bit ID using the following commands:

          `head -c 8 /etc/machine-id`

          (this derives it from the machine-id that systemd generates) or

          `head -c4 /dev/urandom | od -A none -t x4`

          The primary use case is to ensure when using ZFS that a pool isn't imported
          accidentally on a wrong machine.
        '';
      };

      dhcp = {
        enable = mkOption {
          type = types.bool;
          description = ''Whether to enable DHCP globally. This is overrided by individual interface settings. Defaults to true'';
          default = true;
        };
        overrideNameservers = mkOption {
          type = types.bool;
          description = ''Whether to use DHCP nameservers over configured ones. Defaults to false.'';
          default = false;
        };
      };
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
    environment.etc = {
      hostname = mkIf (config.networking.hostName != "") {
        text = config.networking.hostName + "\n";
      };
      "resolv.conf".text = ''${lib.strings.concatLines (lib.lists.forEach config.networking.nameservers (
          x: ''
            nameserver ${x}
          ''
        ))}'';
      "udhcpc/udhcpc.conf".text = "${
        if config.networking.dhcp.overrideNameservers == false
        then "RESOLV_CONF = no"
        else "RESOLV_CONF = /etc/resolv.conf"
      }";
      "nsswitch.conf".text = ''
        hosts:     files dns
        networks:  files dns
      '';

      "network/interfaces".text = ''
        auto lo
        iface lo inet loopback
        ${lib.strings.concatLines (lib.lists.forEach config.networking.interfaces (
          x: ''
            auto ${x.name}
            ${
              if x.dhcp == true || x.dhcp == null && x.ipv4.address == null
              then ''
                iface ${x.name}
                  use dhcp
                  dhcp-program dhcpcd
              ''
              else ''
                iface ${x.name} inet static
                  address ${x.ipv4.address}
                  gateway ${x.ipv4.gateway}
              ''
            }
            ${
              if x.slaac == true || x.slaac == null && x.ipv6.address == null
              then "iface ${x.name} inet6 auto"
              else ''
                iface ${x.name} inet6 static
                  address ${x.ipv6.address}
                  gateway ${x.ipv6.gateway}
              ''
            }
          ''
        ))}
      '';
    };
  };
}
