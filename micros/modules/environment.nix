{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption literalExpression;
  inherit (lib) types;
in {
  options = {
    environment = {
      extraInit = mkOption {
        default = "";
        type = types.lines;
        description = ''
          Shell script code called during global environment initialisation
          after all variables and profileVariables have been set.
          This code is assumed to be shell-independent, which means you should
          stick to pure sh without sh word split.
        '';
      };

      binsh = mkOption {
        default = "${pkgs.busybox}/bin/ash";
        defaultText = literalExpression ''"''${config.system.build.binsh}/bin/sh"'';
        example = literalExpression ''"''${pkgs.dash}/bin/dash"'';
        type = types.path;
        description = ''
          The shell executable that is linked system-wide to `/bin/sh`.
        '';
      };
    };
  };

  config = {
    environment.etc = {
      bashrc.text = "export PATH=/run/current-system/sw/bin";
      profile.text = "export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin";

      "resolv.conf".text = "nameserver 10.0.2.3";

      "nsswitch.conf".text = ''
        hosts:     files  dns   myhostname mymachines
        networks:  files dns
      '';

      "services".source = pkgs.iana-etc + "/etc/services";

      group.text = ''
        root:x:0:
        nixbld:x:30000:nixbld1,nixbld10,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9
      '';
    };
  };
}
