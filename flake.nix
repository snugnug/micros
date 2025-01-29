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
  in {
    packages = {
      armv7l-linux = let
        eval = lib.microsSystem {
          modules = [
            ./rpi_image.nix

            {
              system.build.rpi_firmware = raspi-firmware;
              nixpkgs.hostPlatform = {system = "armv7l-linux";};
              nixpkgs.buildPlatform = {system = "x86_64-linux";};
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
      };
    };

    # Custom library to provide additional utilities for 3rd party consumption.
    # Primarily designed to expose `microsSystem` as, e.g., inputs.micros.lib.microsSystem
    # for when you are building non-supported platforms on your own accord.
    # TODO: extend nixpkgs.lib here
    lib = {
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
    };
  };
}
