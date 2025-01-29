{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption literalExpression;
  inherit (lib) mkIf mkDefault;
  inherit (lib) filterAttrs mapAttrsToList;
  inherit (lib) types;

  cfg = config.nix;
in {
  options = {
    nix = {
      enable = mkOption {
        type = types.bool;
        default = config.not-os.nix.enable;
        description = ''
          Whether to enable Nix.

          Disabling Nix makes the system hard to modify and the Nix programs and configuration
          will not be made available by NixOS itself.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.nix;
        defaultText = literalExpression "pkgs.nix";
        description = ''
          This option specifies the Nix package instance to use throughout the system.
        '';
      };

      nixPath = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          The default Nix expression search path, used by the Nix
          evaluator to look up paths enclosed in angle brackets
          (e.g. `<nixpkgs>`).
        '';
      };

      registry = mkOption {
        default = {};
        type = types.attrsOf (
          types.submodule (
            let
              referenceAttrs = with types;
                attrsOf (oneOf [
                  str
                  int
                  bool
                  path
                  package
                ]);
            in
              {
                config,
                name,
                ...
              }: {
                options = {
                  from = mkOption {
                    type = referenceAttrs;
                    example = {
                      type = "indirect";
                      id = "nixpkgs";
                    };
                    description = "The flake reference to be rewritten.";
                  };

                  to = mkOption {
                    type = referenceAttrs;
                    example = {
                      type = "github";
                      owner = "my-org";
                      repo = "my-nixpkgs";
                    };
                    description = "The flake reference {option}`from` is rewritten to.";
                  };

                  flake = mkOption {
                    type = types.nullOr types.attrs;
                    default = null;
                    example = literalExpression "nixpkgs";
                    description = ''
                      The flake input {option}`from` is rewritten to.
                    '';
                  };

                  exact = mkOption {
                    type = types.bool;
                    default = true;
                    description = ''
                      Whether the {option}`from` reference needs to match exactly. If set,
                      a {option}`from` reference like `nixpkgs` does not
                      match with a reference like `nixpkgs/nixos-20.03`.
                    '';
                  };
                };

                config = {
                  from = mkDefault {
                    type = "indirect";
                    id = name;
                  };

                  to = mkIf (config.flake != null) (
                    mkDefault (
                      {
                        type = "path";
                        path = config.flake.outPath;
                      }
                      // filterAttrs (n: _: n == "lastModified" || n == "rev" || n == "narHash") config.flake
                    )
                  );
                };
              }
          )
        );
        description = "A system-wide flake registry.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.etc."nix/registry.json".text = builtins.toJSON {
      version = 2;
      flakes = mapAttrsToList (_: v: {inherit (v) from to exact;}) cfg.registry;
    };
  };
}
