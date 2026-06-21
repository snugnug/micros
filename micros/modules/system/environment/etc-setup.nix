# Replace setup-etc.pl with a bash implementation.
# Eliminates perl (~51 MiB) from the system closure.
#
# The original script manages /etc/static symlinks, cleans up stale entries,
# and handles mode/uid/gid for copied files. All of this is doable in bash
# with coreutils + findutils (already in the closure).
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  etc' = lib.filter (f: f.enable) (lib.attrValues config.environment.etc);

  buildEtc =
    pkgs.runCommandLocal "etc"
    {
      passthru.targets = map (x: x.target) etc';
    }
    ''
      set -euo pipefail

      makeEtcEntry() {
        src="$1"
        target="$2"
        mode="$3"
        user="$4"
        group="$5"

        if [[ "$src" = *'*'* ]]; then
          mkdir -p "$out/etc/$target"
          for fn in $src; do
              ln -s "$fn" "$out/etc/$target/"
          done
        else
          mkdir -p "$out/etc/$(dirname "$target")"
          if ! [ -e "$out/etc/$target" ]; then
            ln -s "$src" "$out/etc/$target"
          else
            echo "duplicate entry $target -> $src"
            if [ "$(readlink "$out/etc/$target")" != "$src" ]; then
              echo "mismatched duplicate entry $(readlink "$out/etc/$target") <-> $src"
              ret=1
              continue
            fi
          fi

          if [ "$mode" != symlink ]; then
            echo "$mode" > "$out/etc/$target.mode"
            echo "$user" > "$out/etc/$target.uid"
            echo "$group" > "$out/etc/$target.gid"
          fi
        fi
      }

      mkdir -p "$out/etc"
      ${lib.concatMapStringsSep "\n" (
          etcEntry:
            lib.escapeShellArgs [
              "makeEtcEntry"
              "${etcEntry.source}"
              etcEntry.target
              etcEntry.mode
              etcEntry.user
              etcEntry.group
            ]
        )
        etc'}
    '';
in {
  system.activationScripts.etc = lib.mkForce (lib.stringAfter ["users"] ''
    echo "setting up /etc..."
    ${pkgs.nixos-core}/bin/nixos-core setup-etc ${buildEtc}/etc
  '');
}
