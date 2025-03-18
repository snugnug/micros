{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkMerge mkOption mkEnableOption;
  inherit (lib) concatMapStringsSep concatStringsSep attrNames;
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

      interfaces = mkOption {
        default = {};
        type = types.attrsOf (types.submodule {
          options = {
            method = mkOption {
              type = types.enum ["dhcp" "wifi" "static"];
              default = "dhcp";
              description = "Specifies the network configuration method for the interface.";
            };

            wpaConf = mkOption {
              type = types.path;
              default = "";
              description = "Path to the wpa_supplicant configuration file (required for wifi).";
            };

            staticIP = mkOption {
              type = types.str;
              default = "";
              description = "Static IP address in CIDR notation (e.g., 192.168.1.2/24) for static configuration.";
            };
          };
        });
        description = "A mapping of interface names to their network configuration settings.";
      };
    };
  };

  config = mkMerge [
    (mkIf (config.networking.hostName != "") {
      environment.etc.hostname = {
        text = config.networking.hostName + "\n";
      };
    })

    (mkIf (config.networking.interfaces != null) {
      # TODO: use a pkgs.writeShell* here. Just here for testing.
      environment.etc."network-config.sh".text = let
        interfaceNames = attrNames config.networking.interfaces;
      in ''
        #!/bin/sh
        # Generated by MicrOS networking module. Sources basic interface information
        # for script-based networking.

        # List all interfaces
        export NETWORK_INTERFACES="${concatStringsSep " " interfaceNames}"

        ${concatMapStringsSep "\n" (
            ifaceName: iface: let
              method = iface.method;
            in ''
              # Configuration for ${ifaceName}
              ${ifaceName}_METHOD=${method}
              ${
                if method == "wifi"
                then "${ifaceName}_WPA_CONF=${iface.wpaConf}"
                else ""
              }
              ${
                if method == "static"
                then "${ifaceName}_STATIC_IP=${iface.staticIP}"
                else ""
              }
            ''
          )
          config.networking.interfaces}
      '';

      runit.services = {
        networkd = {
          runScript = ''
            #!${pkgs.runtimeShell}
            set -euo pipefail

            error_exit() {
                echo "Error on line $1. Exiting." >&2
                exit 1
            }

            trap 'error_exit $LINENO' ERR

            echo "Starting MicrOS network daemon"

            # Check if the generated configuration file exists.
            CONFIG_FILE="/etc/network-config.sh"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "Configuration file $CONFIG_FILE not found. Exiting." >&2
                exit 1
            fi

            # Source the generated configuration file.
            # TODO: expose the script as an option, and source it directly.
            . "$CONFIG_FILE"

            if [ -z "$${NETWORK_INTERFACES:-}" ]; then
                echo "No network interfaces defined in $CONFIG_FILE. Exiting." >&2
                exit 1
            fi

            # Iterate over each interface defined in NETWORK_INTERFACES.
            for iface in $NETWORK_INTERFACES; do
                # Validate that the method variable for this interface is set.
                iface_method=$(eval echo \$${iface}_METHOD)
                if [ -z "$iface_method" ]; then
                    echo "No method defined for interface $iface. Skipping." >&2
                    continue
                fi

                case "$iface_method" in
                    dhcp)
                        (
                            echo "Configuring $iface for DHCP"
                            ip link set "$iface" up || { echo "Failed to bring up $iface" >&2; exit 1; }
                            exec dhcpcd "$iface"
                        ) &
                        ;;
                    wifi)
                        (
                            echo "Configuring $iface for Wi-Fi"
                            ip link set "$iface" up || { echo "Failed to bring up $iface" >&2; exit 1; }
                            iface_wpa_conf=$(eval echo \$${iface}_WPA_CONF)
                            if [ -z "$iface_wpa_conf" ]; then
                                echo "WPA configuration for $iface not defined. Exiting." >&2
                                exit 1
                            fi
                            # Start wpa_supplicant (using -B to fork in background)
                            if ! wpa_supplicant -B -i "$iface" -c "$iface_wpa_conf"; then
                                echo "wpa_supplicant failed for $iface." >&2
                                exit 1
                            fi
                            # Wait until an IP appears on the interface.
                            timeout=10
                            elapsed=0
                            while ! ip addr show "$iface" | grep -q "inet "; do
                                sleep 1
                                elapsed=$((elapsed + 1))
                                if [ $elapsed -ge $timeout ]; then
                                    echo "Timeout waiting for IP on $iface." >&2
                                    exit 1
                                fi
                            done
                            exec dhcpcd "$iface"
                        ) &
                        ;;
                    static)
                        (
                            echo "Configuring $iface with static IP"
                            ip link set "$iface" up || { echo "Failed to bring up $iface" >&2; exit 1; }
                            if ! ip addr add "$(eval echo \$${iface}_STATIC_IP)" dev "$iface"; then
                                echo "Failed to assign static IP for $iface." >&2
                                exit 1
                            fi
                            # Remain running for supervision.
                            exec sleep infinity
                        ) &
                        ;;
                    *)
                        echo "Unsupported method for interface $iface" >&2
                        ;;
                esac
            done

            # Wait for all background processes.
            wait
          '';
        };
      };
    })
  ];
}
