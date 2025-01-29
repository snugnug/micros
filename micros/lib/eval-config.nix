{
  nixpkgs,
  prefix ? [],
  baseModules ? import ../modules/all-modules.nix,
  modulesLocation ? (builtins.unsafeGetAttrPos "modules" evalConfigArgs).file or null,
  lib ? nixpkgs.lib,
  modules,
  specialArgs ? {},
  ...
} @ evalConfigArgs: let
  # Init system agnostic modules that we import to retain compatibility.
  # While we could simply assimilate those into MicrOS module system, it
  # might be better to *simply import* the files as they are not very
  # likely to cause breaking changes.
  nixpkgsModules = map (x: "${nixpkgs}/nixos/modules/${x}") [
    "system/etc/etc.nix"
    "system/activation/activation-script.nix"
    "system/boot/kernel.nix"
    "config/sysctl.nix"
    "misc/nixpkgs.nix"
    "misc/nixpkgs-flake.nix"
    "misc/assertions.nix"
    "misc/lib.nix"
  ];

  evalModulesMinimal =
    (import (nixpkgs + "/nixos/lib") {
      inherit lib;
      # Implicit use of feature is noted in implementation.
      featureFlags.minimalModules = {};
    })
    .evalModules;

  allUserModules = let
    # Add the invoking file (or specified modulesLocation) as error message location
    # for modules that don't have their own locations; presumably inline modules.
    locatedModules =
      if modulesLocation == null
      then modules
      else map (lib.setDefaultModuleLocation modulesLocation) modules;
  in
    locatedModules;

  # Extra arguments that are useful for constructing a similar configuration.
  modulesModule = {
    config = {
      _module.args = {
        inherit noUserModules baseModules modules;
      };
    };
  };

  nixosWithUserModules = noUserModules.extendModules {modules = allUserModules;};
  withExtraAttrs = configuration:
    configuration
    // {
      inherit (configuration._module.args) pkgs;
      inherit lib;
      extendModules = args: withExtraAttrs (configuration.extendModules args);
    };

  noUserModules = evalModulesMinimal {
    inherit prefix;
    specialArgs =
      {modulesPath = builtins.toString ./.;} // specialArgs;
    modules = baseModules ++ nixpkgsModules ++ [modulesModule];
  };
in
  withExtraAttrs nixosWithUserModules
