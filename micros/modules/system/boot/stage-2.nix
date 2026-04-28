{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  config = {
    system.build.bootStage2 = pkgs.writeTextFile {
      executable = true;
      name = "stage-2-init";
      text = ''
        #! ${pkgs.busybox}/bin/ash
        export PATH="${lib.makeBinPath [pkgs.busybox inputs.nixos-core.packages.${pkgs.stdenv.system}.default]}"
        export SYSTEMD_EXECUTABLE=${pkgs.runit}/bin/runit
        export STAGE2_PATH=/run/booted-system/sw/bin
        REPLACE_WITH_CONTAINER
        exec ${inputs.nixos-core.packages.${pkgs.stdenv.system}.default}/bin/nixos-core stage-2-init --system-config REPLACE_WITH_TOPLEVEL
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
