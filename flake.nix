{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (self) lib;

    forSupportedSystems = lib.genAttrs ["x86_64-linux" "aarch64-linux" "armv7l-linux"];
  in {
    hydraJobs = self.packages;
    packages = forSupportedSystems (system: {
      iso = lib.microsSystem {
        modules = [
          ./micros/modules/profiles/virtualization/iso-image.nix

          {
            nixpkgs.hostPlatform = {inherit system;};
          }
        ];
      };

      zynq = lib.microsSystem {
        modules = [
          ./micros/modules/profiles/hardware/zynq.nix
          ./micros/modules/profiles/hardware/arm32-cross.nix

          {
            nixpkgs.hostPlatform = {inherit system;};
          }
        ];
      };

      qemu = lib.microsSystem {
        modules = [
          ./micros/modules/profiles/virtualization/qemu-guest.nix

          {
            nixpkgs.hostPlatform = {inherit system;};
          }
        ];
      };
    });

    legacyPackages = forSupportedSystems (system: {
      ifupdown-ng = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/ifupdown-ng.nix {};
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
                  config.nixpkgs.flake.source = nixpkgs.outPath;
                })
              ];
          }
          // builtins.removeAttrs args ["modules"]
        );
    });
  };
}
