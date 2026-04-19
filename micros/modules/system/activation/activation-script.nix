{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mapAttrs isString noDepEntry textClosureList attrNames mkOption literalExpression types getBin;
  addAttributeName = mapAttrs (
    a: v:
      v
      // (lib.optionalAttrs (v.text != "") {
        text = ''
          #### Activation script snippet ${a}:
          ${v.text}
        '';
      })
  );
  systemActivationScript = set: let
    set' =
      mapAttrs (
        _: v:
          if isString v
          then (noDepEntry v)
          else v
      )
      set;
    withHeadlines = addAttributeName set';
  in ''

    warn() {
        printf "\033[1;35mwarning:\033[0m %s\n" "$*" >&2
    }
    systemConfig='@out@'

    export PATH=/empty
    for i in ${toString path}; do
        PATH=$PATH:$i/bin:$i/sbin
    done

    _status=0

    # Ensure a consistent umask.
    umask 0022

    ${lib.concatStringsSep "\n" (
      lib.filter (v: v != "") (
        textClosureList withHeadlines (attrNames (lib.filterAttrs (_: v: v.text != "") withHeadlines))
      )
    )}
  '';
  path =
    if (config.boot.isContainer == false)
    then
      (map getBin (with pkgs; [
        coreutils
        gnugrep
        findutils
        getent
        stdenv.cc.libc # nscd in update-users-groups.pl
        shadow
        util-linux # needed for mount and mountpoint
      ]))
    else (with pkgs; map getBin [busybox]);
  scriptType = let
    scriptOptions = {
      deps = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of dependencies. The script will run after these.";
      };
      text = mkOption {
        type = types.lines;
        description = "The content of the script.";
      };
    };
  in
    types.either types.str (types.submodule {
      options = scriptOptions;
    });
in {
  # Custom activation script based off nixos implementation
  # Micros is lighter and therefore can cut out many of the things in the nixos script,
  # especially when run in a container.
  # Micros is currently image based, so dry activations and swappable systems can be removed for more efficient and smaller activation

  options = {
    system.activationScripts = mkOption {
      default = {};
      example = literalExpression ''
        {
          stdio = {
            # Run after /dev has been mounted
            deps = [ "specialfs" ];
            text =
              '''
                # Needed by some programs.
                ln -sfn /proc/self/fd /dev/fd
                ln -sfn /proc/self/fd/0 /dev/stdin
                ln -sfn /proc/self/fd/1 /dev/stdout
                ln -sfn /proc/self/fd/2 /dev/stderr
              ''';
          };
        }
      '';

      description = ''
        A set of shell script fragments that are executed when a NixOS
        system configuration is activated.  Examples are updating
        /etc, creating accounts, and so on.  Since these are executed
        every time you boot the system or run
        {command}`nixos-rebuild`, it's important that they are
        idempotent and fast.
      '';

      type = types.attrsOf scriptType;
      apply = set:
        set
        // {
          script = systemActivationScript set;
        };
    };
    environment.usrbinenv = mkOption {
      default = "${pkgs.busybox}/bin/env";
      defaultText = literalExpression ''"''${pkgs.busybox}/bin/env"'';
      example = literalExpression ''"''${pkgs.coreutils}/bin/env"'';
      type = types.nullOr types.path;
      visible = false;
      description = ''
        The {manpage}`env(1)` executable that is linked system-wide to
        `/usr/bin/env`.
      '';
    };
  };
  config = {
    system.activationScripts.usrbinenv =
      if config.environment.usrbinenv != null
      then ''
        mkdir -p /usr/bin
        chmod 0755 /usr/bin
        ln -sfn ${config.environment.usrbinenv} /usr/bin/.env.tmp
        mv /usr/bin/.env.tmp /usr/bin/env # atomically replace /usr/bin/env
      ''
      else ''
        rm -f /usr/bin/env
        if test -d /usr/bin; then rmdir --ignore-fail-on-non-empty /usr/bin; fi
        if test -d /usr; then rmdir --ignore-fail-on-non-empty /usr; fi
      '';
    system.activationScripts.specialfs = lib.mkIf (config.boot.isContainer == false) ''
      specialMount() {
        local device="$1"
        local mountPoint="$2"
        local options="$3"
        local fsType="$4"

        if mountpoint -q "$mountPoint"; then
          local options="remount,$options"
        else
          mkdir -p "$mountPoint"
          chmod 0755 "$mountPoint"
        fi
        mount -t "$fsType" -o "$options" "$device" "$mountPoint"
      }
      source ${config.system.build.earlyMountScript}
    '';
  };
}
