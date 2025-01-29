{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    raspi-firmware = {
      url = "github:raspberrypi/firmware";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    raspi-firmware,
  }: let
    inherit (self) lib;

    forSupportedSystems = lib.genAttrs ["armv7l-linux"];
  in {
    packages = forSupportedSystems (system: let
      eval = lib.microsSystem {
        modules = [
          ./boards/rpi/base.nix

          {
            system.build.rpi-firmware = raspi-firmware;
            nixpkgs.hostPlatform = {system = "armv7l-linux";};
            nixpkgs.buildPlatform = {system = "x86_64-linux";};

            nixpkgs.overlays = [
              (self: super: {
                openssh = super.openssh.override {
                  withFIDO = false;
                  withKerberos = false;
                };

                util-linux = super.util-linux.override {
                  pamSupport = false;
                  capabilitiesSupport = false;
                  ncursesSupport = false;
                  systemdSupport = false;
                  nlsSupport = false;
                  translateManpages = false;
                };

                utillinuxCurses = self.util-linux;
                utillinuxMinimal = self.util-linux;
                linux_rpi = self.legacyPackages.${system}.linux-rpi;
              })
            ];
          }
        ];
      };

      zynq_eval = lib.microsSystem {
        modules = [
          ./zynq_image.nix

          {
            nixpkgs.hostPlatform = {system = "armv7l-linux";};
            nixpkgs.buildPlatform = {system = "x86_64-linux";};
          }
        ];
      };
    in {
      rpi-image = eval.config.system.build.rpi_image;
      rpi-image-tar = eval.config.system.build.rpi_image_tar;
      rpi-runvm = eval.config.system.build.runvm;
      rpi-toplevel = eval.config.system.build.toplevel;

      zynq-image = zynq_eval.config.system.build.zynq_image;
    });

    legacyPackages = forSupportedSystems (system: {
      linux-rpi = nixpkgs.pkgs.${system}.callPackage ./pkgs/linux-rpi.nix {};
    });

    # Custom library to provide additional utilities for 3rd party consumption.
    # Primarily designed to expose `microsSystem` as, e.g., inputs.micros.lib.microsSystem
    # for when you are building non-supported platforms on your own accord.
    # TODO: extend nixpkgs.lib here
    lib = nixpkgs.lib.extend (_: _: {
      microsSystem = args:
        import ./micros/lib/eval-config.nix (
          {
            inherit nixpkgs;

            # Allow system to be set modularly in nixpkgs.system.
            # We set it to null, to remove the "legacy" entrypoint's
            # non-hermetic default.
            system = null;

            modules =
              args.modules
              ++ [
                # This module is injected here since it exposes the nixpkgs self-path in as
                # constrained of contexts as possible to avoid more things depending on it and
                # introducing unnecessary potential fragility to changes in flakes itself.
                #
                # See: failed attempt to make pkgs.path not copy when using flakes:
                # https://github.com/NixOS/nixpkgs/pull/153594#issuecomment-1023287913
                ({
                  config,
                  pkgs,
                  lib,
                  ...
                }: {
                  config.nixpkgs.flake.source = self.outPath;
                })
              ];
          }
          // builtins.removeAttrs args ["modules"]
        );
    });
  };
}
