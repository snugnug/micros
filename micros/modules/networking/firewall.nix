{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) mkIf;
  inherit (lib) types;
  ifaceSet = lib.concatStringsSep ", " (map (x: ''"${x}"'') cfg.trustedInterfaces);

  portsToNftSet = ports: portRanges:
    lib.concatStringsSep ", " (
      map (x: toString x) ports ++ map (x: "${toString x.from}-${toString x.to}") portRanges
    );
  cfg = config.networking.firewall;
  interfaceOpts = {
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [];
      example = [22];
      description = ''
        List of open TCP ports.
      '';
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [];
      example = [53];
      description = ''
        List of open UDP ports.
      '';
    };
    allowedTCPPortRanges = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.port);
      default = [];
      example = [
        {
          from = 32000;
          to = 32768;
        }
      ];
      description = ''
        Range of open TCP ports.
      '';
    };
    allowedUDPPortRanges = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.port);
      default = [];
      example = [
        {
          from = 32000;
          to = 32768;
        }
      ];
      description = ''
        Range of open UDP ports.
      '';
    };
  };
in {
  options.networking.firewall =
    {
      enable = lib.mkEnableOption ''firewall'';
      logRefusedConnections = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to log rejected or dropped incoming connections.
          Note: The logs are found in the kernel logs, i.e. dmesg
          or journalctl -k.
        '';
      };

      logRefusedPackets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to log all rejected or dropped incoming packets.
          This tends to give a lot of log messages, so it's mostly
          useful for debugging.
          Note: The logs are found in the kernel logs, i.e. dmesg
          or journalctl -k.
        '';
      };

      logRefusedUnicastsOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          If {option}`networking.firewall.logRefusedPackets`
          and this option are enabled, then only log packets
          specifically directed at this machine, i.e., not broadcasts
          or multicasts.
        '';
      };

      rejectPackets = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          If set, refused packets are rejected rather than dropped
          (ignored).  This means that an ICMP "port unreachable" error
          message is sent back to the client (or a TCP RST packet in
          case of an existing connection).  Rejecting packets makes
          port scanning somewhat easier.
        '';
      };

      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["enp0s2"];
        description = ''
          Traffic coming in from these interfaces will be accepted
          unconditionally.  Traffic from the loopback (lo) interface
          will always be accepted.
        '';
      };

      allowPing = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to respond to incoming ICMPv4 echo requests
          ("pings").  ICMPv6 pings are always allowed because the
          larger address space of IPv6 makes network scanning much
          less effective.
        '';
      };

      pingLimit = lib.mkOption {
        type = lib.types.nullOr (lib.types.separatedString " ");
        default = null;
        example = "--limit 1/minute --limit-burst 5";
        description = ''
          If pings are allowed, this allows setting rate limits on them.

          For the iptables based firewall, it should be set like
          "--limit 1/minute --limit-burst 5".

          For the nftables based firewall, it should be set like
          "2/second" or "1/minute burst 5 packets".
        '';
      };

      checkReversePath = lib.mkOption {
        type = lib.types.either lib.types.bool (
          lib.types.enum [
            "strict"
            "loose"
          ]
        );
        default = true;
        defaultText = lib.literalMD "`true` except if the iptables based firewall is in use and the kernel lacks rpfilter support";
        example = "loose";
        description = ''
          Performs a reverse path filter test on a packet.  If a reply
          to the packet would not be sent via the same interface that
          the packet arrived on, it is refused.

          If using asymmetric routing or other complicated routing, set
          this option to loose mode or disable it and setup your own
          counter-measures.

          This option can be either true (or "strict"), "loose" (only
          drop the packet if the source address is not reachable via any
          interface) or false.
        '';
      };

      logReversePathDrops = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Logs dropped packets failing the reverse path filter test if
          the option networking.firewall.checkReversePath is enabled.
        '';
      };

      filterForward = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable filtering in IP forwarding.

          This option only works with the nftables based firewall.
        '';
      };

      connectionTrackingModules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [
          "ftp"
          "irc"
          "sane"
          "sip"
          "tftp"
          "amanda"
          "h323"
          "netbios_sn"
          "pptp"
          "snmp"
        ];
        description = ''
          List of connection-tracking helpers that are auto-loaded.
          The complete list of possible values is given in the example.

          As helpers can pose as a security risk, it is advised to
          set this to an empty list and disable the setting
          networking.firewall.autoLoadConntrackHelpers unless you
          know what you are doing. Connection tracking is disabled
          by default.

          Loading of helpers is recommended to be done through the
          CT target.  More info:
          <https://home.regit.org/netfilter-en/secure-use-of-helpers/>
        '';
      };

      autoLoadConntrackHelpers = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to auto-load connection-tracking helpers.
          See the description at networking.firewall.connectionTrackingModules

          (needs kernel 3.5+)
        '';
      };
      extraInputRules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = "ip6 saddr { fc00::/7, fe80::/10 } tcp dport 24800 accept";
        description = ''
          Additional nftables rules to be appended to the input-allow
          chain.

          This option only works with the nftables based firewall.
        '';
      };

      extraForwardRules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = "iifname wg0 accept";
        description = ''
          Additional nftables rules to be appended to the forward-allow
          chain.

          This option only works with the nftables based firewall.
        '';
      };

      extraReversePathFilterRules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = "fib daddr . mark . iif type local accept";
        description = ''
          Additional nftables rules to be appended to the rpfilter-allow
          chain.

          This option only works with the nftables based firewall.
        '';
      };
      interfaces = lib.mkOption {
        default = {};
        type = with lib.types; attrsOf (submodule [{options = interfaceOpts;}]);
        description = ''
          Interface-specific open ports.
        '';
      };

      allInterfaces = lib.mkOption {
        internal = true;
        visible = false;
        default =
          {
            default = lib.mapAttrs (name: value: cfg.${name}) interfaceOpts;
          }
          // cfg.interfaces;
        type = with lib.types; attrsOf (submodule [{options = interfaceOpts;}]);
        description = ''
          All open ports.
        '';
      };
    }
    // interfaceOpts;
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.extraCommands == "";
        message = "extraCommands is incompatible with the nftables based firewall: ${cfg.extraCommands}";
      }
      {
        assertion = cfg.extraStopCommands == "";
        message = "extraStopCommands is incompatible with the nftables based firewall: ${cfg.extraStopCommands}";
      }
      {
        assertion = cfg.pingLimit == null || !(lib.hasPrefix "--" cfg.pingLimit);
        message = "nftables syntax like \"2/second\" should be used in networking.firewall.pingLimit";
      }
      {
        assertion = config.networking.nftables.rulesetFile == null;
        message = "networking.nftables.rulesetFile conflicts with the firewall";
      }
    ];

    networking.nftables.tables."micros-fw".family = "inet";
    networking.nftables.tables."micros-fw".content = ''
      ${lib.optionalString (cfg.checkReversePath != false) ''
        chain rpfilter {
          type filter hook prerouting priority mangle + 10; policy drop;

          meta nfproto ipv4 udp sport . udp dport { 67 . 68, 68 . 67 } accept comment "DHCPv4 client/server"
          fib saddr . mark ${lib.optionalString (cfg.checkReversePath != "loose") ". iif"} oif exists accept

          jump rpfilter-allow

          ${lib.optionalString cfg.logReversePathDrops ''
          log level info prefix "rpfilter drop: "
        ''}

        }
      ''}

      chain rpfilter-allow {
        ${cfg.extraReversePathFilterRules}
      }

      chain input {
        type filter hook input priority filter; policy drop;

        ${lib.optionalString (
        ifaceSet != ""
      ) ''iifname { ${ifaceSet} } accept comment "trusted interfaces"''}

        # Some ICMPv6 types like NDP is untracked
        ct state vmap {
          invalid : drop,
          established : accept,
          related : accept,
          new : jump input-allow,
          untracked: jump input-allow,
        }

        ${lib.optionalString cfg.logRefusedConnections ''
        tcp flags syn / fin,syn,rst,ack log level info prefix "refused connection: "
      ''}
        ${lib.optionalString (cfg.logRefusedPackets && !cfg.logRefusedUnicastsOnly) ''
        pkttype broadcast log level info prefix "refused broadcast: "
        pkttype multicast log level info prefix "refused multicast: "
      ''}
        ${lib.optionalString cfg.logRefusedPackets ''
        pkttype host log level info prefix "refused packet: "
      ''}

        ${lib.optionalString cfg.rejectPackets ''
        meta l4proto tcp reject with tcp reset
        reject
      ''}

      }

      chain input-allow {

        ${lib.concatStrings (
        lib.mapAttrsToList (
          iface: cfg: let
            ifaceExpr = lib.optionalString (iface != "default") "iifname ${iface}";
            tcpSet = portsToNftSet cfg.allowedTCPPorts cfg.allowedTCPPortRanges;
            udpSet = portsToNftSet cfg.allowedUDPPorts cfg.allowedUDPPortRanges;
          in ''
            ${lib.optionalString (tcpSet != "") "${ifaceExpr} tcp dport { ${tcpSet} } accept"}
            ${lib.optionalString (udpSet != "") "${ifaceExpr} udp dport { ${udpSet} } accept"}
          ''
        )
        cfg.allInterfaces
      )}

        ${lib.optionalString cfg.allowPing ''
        icmp type echo-request ${
          lib.optionalString (cfg.pingLimit != null) "limit rate ${cfg.pingLimit}"
        } accept comment "allow ping"
      ''}

        icmpv6 type != { nd-redirect, 139 } accept comment "Accept all ICMPv6 messages except redirects and node information queries (type 139).  See RFC 4890, section 4.4."
        ip6 daddr fe80::/64 udp dport 546 accept comment "DHCPv6 client"

        ${cfg.extraInputRules}

      }

      ${lib.optionalString cfg.filterForward ''
        chain forward {
          type filter hook forward priority filter; policy drop;

          ct state vmap {
            invalid : drop,
            established : accept,
            related : accept,
            new : jump forward-allow,
            untracked : jump forward-allow,
          }

        }

        chain forward-allow {

          icmpv6 type != { router-renumbering, 139 } accept comment "Accept all ICMPv6 messages except renumbering and node information queries (type 139).  See RFC 4890, section 4.3."

          ct status dnat accept comment "allow port forward"

          ${cfg.extraForwardRules}

        }
      ''}
    '';
  };
}
