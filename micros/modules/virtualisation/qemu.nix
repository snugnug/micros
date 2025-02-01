{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption literalExpression;
  inherit (lib) flip concatMapStrings;
  inherit (lib) types;

  cfg = config.virtualisation;
in {
  options = {
    virtualisation = {
      memorySize = mkOption {
        type = types.ints.positive;
        default = 1024;
        description = ''
          The memory size in megabytes of the virtual machine.
        '';
      };

      cores = mkOption {
        type = types.ints.positive;
        default = 1;
        description = ''
          Specify the number of cores the guest is permitted to use.
          The number can be higher than the available cores on the
          host system.
        '';
      };

      forwardPorts = mkOption {
        type = types.listOf (
          types.submodule {
            options.from = mkOption {
              type = types.enum [
                "host"
                "guest"
              ];
              default = "host";
              description = ''
                Controls the direction in which the ports are mapped:

                - `"host"` means traffic from the host ports
                  is forwarded to the given guest port.
                - `"guest"` means traffic from the guest ports
                  is forwarded to the given host port.
              '';
            };

            options.proto = mkOption {
              type = types.enum [
                "tcp"
                "udp"
              ];
              default = "tcp";
              description = "The protocol to forward.";
            };

            options.host.address = mkOption {
              type = types.str;
              default = "";
              description = "The IPv4 address of the host.";
            };

            options.host.port = mkOption {
              type = types.port;
              description = "The host port to be mapped.";
            };

            options.guest.address = mkOption {
              type = types.str;
              default = "";
              description = "The IPv4 address on the guest VLAN.";
            };

            options.guest.port = mkOption {
              type = types.port;
              description = "The guest port to be mapped.";
            };
          }
        );
        default = [];
        example = literalExpression ''
          [
            # forward local port 2222 -> 22, to ssh into the VM
            { from = "host"; host.port = 2222; guest.port = 22; }

            # forward local port 80 -> 10.0.2.10:80 in the VLAN
            { from = "guest";
              guest.address = "10.0.2.10"; guest.port = 80;
              host.address = "127.0.0.1"; host.port = 80;
            }
          ]
        '';
        description = ''
          When using the SLiRP user networking (default), this option allows to
          forward ports to/from the host/guest.

          ::: {.warning}
          If the NixOS firewall on the virtual machine is enabled, you also
          have to open the guest ports to enable the traffic between host and
          guest.
          :::

          ::: {.note}
          Currently QEMU supports only IPv4 forwarding.
          :::
        '';
      };

      networkingOptions = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [
          "-net nic,netdev=user.0,model=virtio"
          "-netdev user,id=user.0,\${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"
        ];
        description = ''
          Networking-related command-line options that should be passed to qemu.
          The default is to use userspace networking (SLiRP).
          See the [QEMU Wiki on Networking](https://wiki.qemu.org/Documentation/Networking) for details.

          If you override this option, be advised to keep
          `''${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}` (as seen in the example)
          to keep the default runtime behaviour.
        '';
      };
    };
  };

  config = let
    networkOpts = let
      forwardingOptions = flip concatMapStrings cfg.forwardPorts (
        {
          proto,
          from,
          host,
          guest,
        }:
          if from == "host"
          then
            "hostfwd=${proto}:${host.address}:${toString host.port}-"
            + "${guest.address}:${toString guest.port},"
          else
            "'guestfwd=${proto}:${guest.address}:${toString guest.port}-"
            + "cmd:${pkgs.netcat}/bin/nc ${host.address} ${toString host.port}',"
      );
    in [
      "-net nic,netdev=user.0,model=virtio"
      "-netdev user,id=user.0,${forwardingOptions}"
    ];

    startVM = ''
      #! ${pkgs.runtimeShell}

      set -e

      exec ${pkgs.qemu}/bin/qemu-kvm \
        -name ${config.system.name} \
        -m ${toString cfg.memorySize} \
        -smp ${toString cfg.cores} \
        -no-reboot \
        -device virtio-rng-pci \
        -drive index=0,id=drive1,file=${config.system.build.squashfs},readonly=on,media=cdrom,format=raw,if=virtio \
        -kernel ${config.system.build.kernel}/bzImage \
        -initrd ${config.system.build.initialRamdisk}/initrd \
        -nographic \
        ${lib.concatStringsSep " " networkOpts} \
        -append "console=ttyS0 ${toString config.boot.kernelParams} quiet panic=-1"
    '';
  in {
    system.build.runvm =
      pkgs.runCommand "micros-vm"
      {
        preferLocalBuild = true;
        meta.mainProgram = "run-${config.system.name}-vm";
      }
      ''
        mkdir -p $out/bin
        ln -s ${pkgs.writeScript "run-nixos-vm" startVM} $out/bin/run-${config.system.name}-vm
      '';
  };
}
