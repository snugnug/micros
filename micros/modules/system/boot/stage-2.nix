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
  };
}
