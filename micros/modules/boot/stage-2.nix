{
  config,
  pkgs,
  lib,
  ...
}: {
  config = {
    system.build.bootStage2 = pkgs.replaceVarsWith {
      src = ./stage-2-init.sh;
      isExecutable = true;
      replacements = {
        shell = "${pkgs.busybox}/bin/ash";
        path = lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ];

        # The Runit executable to be run at the end of the script.
        runitExecutable = "${pkgs.runit}/bin/runit";

        systemConfig = null;

        postBootCommands = pkgs.writeText "local-cmds" ''
          ${config.not-os.postBootCommands}
        '';
      };
    };
  };
}
