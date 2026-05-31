{
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.oci-tool = {
    url = "github:damitusthyyeetus123/oci-tool";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.nixos-core = {
    url = "github:feel-co/nixos-core";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = {
    self,
    nixpkgs,
    oci-tool,
    nixos-core,
    ...
  } @ inputs: let
    inherit (self) lib;

    forSupportedSystems = lib.genAttrs ["x86_64-linux" "aarch64-linux" "armv7l-linux"];
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    # FIXME: syslinux is not supported on aarch64-linux, and this breaks 'nix flake show'
    # We currently don't have Hydra set up, so it's safe to comment this out for now.
    # We'll add this back if we can fix/replace syslinux, or if we choose to filter any
    # specific systems.
    # hydraJobs = self.packages;

    packages = forSupportedSystems (system:
      {
        qemu =
          (lib.microsSystem {
            specialArgs = {inherit inputs lib;};
            modules = [
              ./micros/modules/profiles/virtualization/qemu-guest.nix

              {
                nixpkgs.hostPlatform = {inherit system;};
              }
            ];
          }).config.system.build.runvm;
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        lxc =
          (lib.microsSystem {
            specialArgs = {inherit inputs lib;};
            modules = [
              ./micros/modules/profiles/virtualization/lxc-profile.nix
              {
                nixpkgs.hostPlatform = {
                  inherit system;
                  config = "x86_64-unknown-linux-musl";
                };
              }
            ];
          }).config.system.build.ociImage;

        iso =
          (lib.microsSystem
            {
              specialArgs = {inherit inputs lib;};
              modules = [
                ./micros/modules/profiles/virtualization/iso-image.nix

                {
                  nixpkgs.hostPlatform = {
                    inherit system;
                  };
                }
              ];
            }).config.system.build.image;
      });

    legacyPackages = forSupportedSystems (system: let
      pkgs = pkgsFor system;
    in {
      ifupdown-ng = pkgs.callPackage ./pkgs/ifupdown-ng.nix {};
    });

    # Custom library to provide additional utilities for 3rd party consumption.
    # Primarily designed to expose `microsSystem` as, e.g., inputs.micros.lib.microsSystem
    # for when you are building non-supported platforms on your own accord.
    lib = import ./lib {
      inherit nixpkgs nixos-core oci-tool;

      micros-lib = ./micros/lib/eval-config.nix;
    };
  };
}
