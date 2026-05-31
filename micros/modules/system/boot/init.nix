{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  inherit (lib) types;
in {
  options = {
    boot.init = {
      system = mkOption {
        type = types.str;
        default = "runit";
        description = ''
          Init backend used after stage-2 activation has completed.
        '';
      };

      executable = mkOption {
        type = with types; either path str;
        default = "${pkgs.runit}/bin/runit";
        defaultText = lib.literalExpression ''"''${pkgs.runit}/bin/runit"'';
        description = ''
          Executable that stage 2 will hand off to as PID 1.
        '';
      };

      stage2Path = mkOption {
        type = types.str;
        default = "/run/booted-system/sw/bin";
        description = ''
          PATH value used by stage 2 before handing off to the init backend.
        '';
      };

      backendAvailable = mkOption {
        type = types.bool;
        default = false;
        internal = true;
        description = ''
          Whether a module for the selected init backend is available.
        '';
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = config.boot.init.backendAvailable;
        message = ''
          boot.init.system is set to "${config.boot.init.system}", but MicrOS
          does not provide that init backend.
        '';
      }
    ];
  };
}
