{
  config,
  pkgs,
  lib,
  ...
}: {
  config = {
    system.build.bootStage2 = pkgs.writeTextFile {
      executable = true;
      name = "stage-2-init";
      text = ''
        #! ${pkgs.busybox}/bin/ash
        export PATH="${lib.makeBinPath [pkgs.busybox pkgs.nixos-core]}"
        export SYSTEMD_EXECUTABLE=${lib.escapeShellArg config.boot.init.executable}
        export STAGE2_PATH=${lib.escapeShellArg config.boot.init.stage2Path}
        REPLACE_WITH_CONTAINER
        exec ${pkgs.nixos-core}/bin/nixos-core stage-2-init --system-config REPLACE_WITH_TOPLEVEL
      '';
    };

    #    system.build.bootStage2 = pkgs.replaceVarsWith {
    #src = ./stage-2-init.sh;
    #isExecutable = true;
    #
    #replacements = {
    #  shell = "${pkgs.busybox}/bin/ash";
    #  systemConfig = null; # replaced in ../activation/top-level.nix

    # path = lib.makeBinPath ([
    #     pkgs.busybox
    #   ]
    #     ++ (lib.lists.optionals (config.boot.isContainer == false) [pkgs.util-linuxMinimal]));

    # The Runit executable to be run at the end of the script.
    # runitExecutable = "${pkgs.runit}/bin/runit";

    # inherit (config.system.build) earlyMountScript;

    # postBootCommands = pkgs.writeText "local-cmds" ''
    #     ${config.not-os.postBootCommands}
    #   '';
    # };
    #};
  };
}
