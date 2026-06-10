{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption;
  wrappers = lib.filterAttrs (name: value: value.enable) config.security.wrappers;
  inherit (config.security) wrapperDir;
  parentWrapperDir = dirOf wrapperDir;
  securityWrapper = sourceProg:
    pkgs.pkgsStatic.callPackage ./wrapper-pkg.nix {
      inherit sourceProg;

      # glibc definitions of insecure environment variables
      #
      # We extract the single header file we need into its own derivation,
      # so that we don't have to pull full glibc sources to build wrappers.
      #
      # They're taken from pkgs.glibc so that we don't have to keep as close
      # an eye on glibc changes. Not every relevant variable is in this header,
      # so we maintain a slightly stricter list in wrapper.c itself as well.
      unsecvars = lib.overrideDerivation (pkgs.srcOnly pkgs.glibc) (
        {name, ...}: {
          name = "${name}-unsecvars";
          installPhase = ''
            mkdir $out
            cp sysdeps/generic/unsecvars.h $out
          '';
        }
      );
    };
  fileModeType = let
    # taken from the chmod(1) man page
    symbolic = "[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+";
    numeric = "[-+=]?[0-7]{0,4}";
    mode = "((${symbolic})(,${symbolic})*)|(${numeric})";
  in
    lib.types.strMatching mode // {description = "file mode string";};

  wrapperType = lib.types.submodule (
    {
      name,
      config,
      ...
    }: {
      options.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable the wrapper.";
      };
      options.source = lib.mkOption {
        type = lib.types.path;
        description = "The absolute path to the program to be wrapped.";
      };
      options.program = lib.mkOption {
        type = with lib.types; nullOr str;
        default = name;
        description = ''
          The name of the wrapper program. Defaults to the attribute name.
        '';
      };
      options.owner = lib.mkOption {
        type = lib.types.str;
        description = "The owner of the wrapper program.";
      };
      options.group = lib.mkOption {
        type = lib.types.str;
        description = "The group of the wrapper program.";
      };
      options.permissions = lib.mkOption {
        type = fileModeType;
        default = "u+rx,g+x,o+x";
        example = "a+rx";
        description = ''
          The permissions of the wrapper program. The format is that of a
          symbolic or numeric file mode understood by {command}`chmod`.
        '';
      };
      options.capabilities = lib.mkOption {
        type = lib.types.commas;
        default = "";
        description = ''
          A comma-separated list of capability clauses to be given to the
          wrapper program. The format for capability clauses is described in the
          “TEXTUAL REPRESENTATION” section of the {manpage}`cap_from_text(3)`
          manual page. For a list of capabilities supported by the system, check
          the {manpage}`capabilities(7)` manual page.

          ::: {.note}
          `cap_setpcap`, which is required for the wrapper
          program to be able to raise caps into the Ambient set is NOT raised
          to the Ambient set so that the real program cannot modify its own
          capabilities!! This may be too restrictive for cases in which the
          real program needs cap_setpcap but it at least leans on the side
          security paranoid vs. too relaxed.
          :::
        '';
      };
      options.setuid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add the setuid bit the wrapper program.";
      };
      options.setgid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add the setgid bit the wrapper program.";
      };
    }
  );

  ###### Activation script for the setcap wrappers
  mkSetcapProgram = {
    program,
    capabilities,
    source,
    owner,
    group,
    permissions,
    ...
  }: ''
    cp ${securityWrapper source}/bin/security-wrapper "$wrapperDir/${program}"

    # Prevent races
    chmod 0000 "$wrapperDir/${program}"
    chown ${owner}:${group} "$wrapperDir/${program}"

    # Set desired capabilities on the file plus cap_setpcap so
    # the wrapper program can elevate the capabilities set on
    # its file into the Ambient set.
    ${pkgs.libcap.out}/bin/setcap "cap_setpcap,${capabilities}" "$wrapperDir/${program}"

    # Set the executable bit
    chmod ${permissions} "$wrapperDir/${program}"
  '';

  ###### Activation script for the setuid wrappers
  mkSetuidProgram = {
    program,
    source,
    owner,
    group,
    setuid,
    setgid,
    permissions,
    ...
  }: ''
    cp ${securityWrapper source}/bin/security-wrapper "$wrapperDir/${program}"

    # Prevent races
    chmod 0000 "$wrapperDir/${program}"
    chown ${owner}:${group} "$wrapperDir/${program}"

    chmod "u${
      if setuid
      then "+"
      else "-"
    }s,g${
      if setgid
      then "+"
      else "-"
    }s,${permissions}" "$wrapperDir/${program}"
  '';

  mkWrappedPrograms = map (
    opts:
      if opts.capabilities != ""
      then mkSetcapProgram opts
      else mkSetuidProgram opts
  ) (lib.attrValues wrappers);
in {
  options = {
    security.wrapperDir = mkOption {
      type = lib.types.path;
      default = "/run/wrappers/bin";
      internal = true;
    };
    security.wrappers = lib.mkOption {
      type = lib.types.attrsOf wrapperType;
      default = {};
      example = lib.literalExpression ''
        {
          # a setuid root program
          doas =
            { setuid = true;
              owner = "root";
              group = "root";
              source = "''${pkgs.doas}/bin/doas";
            };

          # a setgid program
          locate =
            { setgid = true;
              owner = "root";
              group = "mlocate";
              source = "''${pkgs.locate}/bin/locate";
            };

          # a program with the CAP_NET_RAW capability
          ping =
            { owner = "root";
              group = "root";
              capabilities = "cap_net_raw+ep";
              source = "''${pkgs.iputils.out}/bin/ping";
            };
        }
      '';
      description = ''
        This option effectively allows adding setuid/setgid bits, capabilities,
        changing file ownership and permissions of a program without directly
        modifying it. This works by creating a wrapper program in a directory
        (not configurable), which is then added to the shell `PATH`.
      '';
    };
  };
  config = {
    assertions =
      lib.mapAttrsToList (name: opts: {
        assertion = opts.setuid || opts.setgid -> opts.capabilities == "";
        message = ''
          The security.wrappers.${name} wrapper is not valid:
              setuid/setgid and capabilities are mutually exclusive.
        '';
      })
      wrappers;

    security.wrappers = let
      mkSetuidRoot = source: {
        setuid = true;
        owner = "root";
        group = "root";
        inherit source;
      };
    in {
      # These are mount related wrappers that require the +s permission.
      mount = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/mount";
      umount = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/umount";
    };

    micros.services.suid-sgid-wrappers = {
      type = "oneshot";
      startOnBoot = true;
      startScript = ''
        #!${pkgs.busybox}/bin/ash

        chmod 755 "${parentWrapperDir}"

        # We want to place the tmpdirs for the wrappers to the parent dir.
        wrapperDir=$(mktemp --directory --tmpdir="${parentWrapperDir}" wrappers.XXXXXXXXXX)
        chmod a+rx "$wrapperDir"

        ${lib.concatStringsSep "\n" mkWrappedPrograms}

        if [ -L ${wrapperDir} ]; then
          # Atomically replace the symlink
          # See https://axialcorps.com/2013/07/03/atomically-replacing-files-and-directories/
          old=$(readlink -f ${wrapperDir})
          if [ -e "${wrapperDir}-tmp" ]; then
            rm --force --recursive "${wrapperDir}-tmp"
          fi
          ln --symbolic --force --no-dereference "$wrapperDir" "${wrapperDir}-tmp"
          mv --no-target-directory "${wrapperDir}-tmp" "${wrapperDir}"
          rm --force --recursive "$old"
        else
          # For initial setup
          ln --symbolic "$wrapperDir" "${wrapperDir}"
        fi
      '';
    };
  };
}
