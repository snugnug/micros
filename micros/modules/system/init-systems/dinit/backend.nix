{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    attrNames
    concatLines
    filterAttrs
    mapAttrs'
    mkPackageOption
    ;

  serviceTypes = {
    longrun = "process";
    oneshot = "scripted";
  };

  serviceBuilder =
    services:
    let
      services' = filterAttrs (_: v: v.enable && v.startScript != null) services;
    in
    (mapAttrs' (name: value: {
      name = "dinit.d/${name}";
      value.text =
        "type = ${serviceTypes.${value.type}}\n"
        + "command = ${pkgs.writeScript "${value.name}-start" value.startScript}\n"
        + "log-type = buffer\n"
        + concatLines (map (x: "depends-on: ${x}") value.dependencies);
    }) services')
    // {
      "dinit.d/boot".text = ''
        type = internal
        ${concatLines (
          map (name: "waits-for: ${name}") (attrNames (filterAttrs (_: v: v.startOnBoot) services'))
        )}
      '';
    };
in
{
  options.dinit.package = mkPackageOption pkgs "dinit" { };

  config.boot.init.availableBackends.dinit = {
    name = "dinit";
    executable = pkgs.writeScript "dinit-init" ''
      #!${lib.getExe' pkgs.busybox "ash"}
      PATH=/run/wrappers/bin:/run/booted-system/sw/bin
      mkdir -p /bin
      ln -sfn ${config.environment.binsh} /bin/sh
      exec ${lib.getExe' config.dinit.package "dinit"}
    '';
    serviceBuilder = serviceBuilder;
    requiredPackages = [ config.dinit.package ];
    supportedFeatures = [ "dependencies" ];
  };
}
