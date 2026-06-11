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
  inputs.ndg.url = "github:feel-co/ndg";
  outputs = {
    self,
    nixpkgs,
    oci-tool,
    nixos-core,
    ndg,
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
        docs = ndg.packages.${system}.ndg-builder.override {
          title = "Micros Documentation";
          evaluatedModules = lib.microsSystem {
            modules = [
              {
                nixpkgs.hostPlatform = {inherit system;};
              }
            ];
            specialArgs = {inherit inputs lib;};
          };

          transformOptions = opt:
            opt
            // {
              declarations = let
                inherit (lib) hasPrefix removePrefix pipe;
                basePathStr = toString ./.;
                nixpkgsPathStr = toString ((pkgsFor system).path);
              in
                map
                (decl: let
                  declStr = toString decl;
                in
                  if hasPrefix basePathStr declStr
                  then
                    pipe declStr [
                      (removePrefix basePathStr)
                      (removePrefix "/")
                      (x: {
                        url = "https://github.com/snugnug/micros/blob/master/${x}";
                        name = "<micros/${x}>";
                      })
                    ]
                  else if decl == "lib/modules.nix"
                  then {
                    url = "https://github.com/NixOS/nixpkgs/blob/master/${decl}";
                    name = "<nixpkgs/lib/modules.nix>";
                  }
                  else if hasPrefix nixpkgsPathStr declStr
                  then
                    pipe declStr [
                      (removePrefix nixpkgsPathStr)
                      (removePrefix "/")
                      (x: {
                        url = "https://github.com/NixOS/nixpkgs/blob/master/${x}";
                        name = "<nixpkgs/${x}>";
                      })
                    ]
                  else decl)
                opt.declarations;
            };
          generateSearch = true;
          highlightCode = true;
          optionsDepth = 10;
          checkModules = true;

          moduleName = "micros";
          basePath = ./.;
          repoPath = "https://github.com/snugnug/micros/blob/master";
        };
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
          lib.microsSystem
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
          };
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
      dag-types-lib = ./micros/lib/types/dag.nix;
      dag-lib = ./micros/lib/dag.nix;
      micros-lib = ./micros/lib/eval-config.nix;
    };
  };
}
