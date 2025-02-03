{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption literalExpression;
  inherit (lib) types;
in {
  options.system.name = mkOption {
    type = types.str;
    default =
      if config.networking.hostName == ""
      then "unnamed"
      else config.networking.hostName;
    defaultText = literalExpression ''
      if config.networking.hostName == ""
      then "unnamed"
      else config.networking.hostName;
    '';
    description = ''
      The name of the system used in the {option}`system.build.toplevel` derivation.

      That derivation has the following name:
      `"nixos-system-''${config.system.name}-''${config.system.nixos.label}"`
    '';
  };
}
