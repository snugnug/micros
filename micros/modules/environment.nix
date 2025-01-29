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
      profile.text = "export PATH=/run/current-system/sw/bin";

      "resolv.conf".text = "nameserver 10.0.2.3";

      passwd.text = ''
        root:x:0:0:System administrator:/root:/run/current-system/sw/bin/bash
        sshd:x:498:65534:SSH privilege separation user:/var/empty:/run/current-system/sw/bin/nologin
        toxvpn:x:1010:65534::/var/lib/toxvpn:/run/current-system/sw/bin/nologin
        nixbld1:x:30001:30000:Nix build user 1:/var/empty:/run/current-system/sw/bin/nologin
        nixbld2:x:30002:30000:Nix build user 2:/var/empty:/run/current-system/sw/bin/nologin
        nixbld3:x:30003:30000:Nix build user 3:/var/empty:/run/current-system/sw/bin/nologin
        nixbld4:x:30004:30000:Nix build user 4:/var/empty:/run/current-system/sw/bin/nologin
        nixbld5:x:30005:30000:Nix build user 5:/var/empty:/run/current-system/sw/bin/nologin
        nixbld6:x:30006:30000:Nix build user 6:/var/empty:/run/current-system/sw/bin/nologin
        nixbld7:x:30007:30000:Nix build user 7:/var/empty:/run/current-system/sw/bin/nologin
        nixbld8:x:30008:30000:Nix build user 8:/var/empty:/run/current-system/sw/bin/nologin
        nixbld9:x:30009:30000:Nix build user 9:/var/empty:/run/current-system/sw/bin/nologin
        nixbld10:x:30010:30000:Nix build user 10:/var/empty:/run/current-system/sw/bin/nologin
      '';

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
