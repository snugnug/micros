{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) mkIf;
  inherit (lib) types;

  cfg = config.security.pam;
in {
  options = {
    security = {
      pam = {
        enable = mkEnableOption "PAM";

        # TODO: this is a hack. Almost not at all modular, and absolutely not sanitary.
        # Ideally we should generate PAM configuration dynamically, without what the
        # NixOS module is doing (horrible horrible time for anyone planning to look at it)
        loginText = mkOption {
          internal = true;
          type = types.lines;
          default = ''
            account required ${pkgs.linux-pam}/lib/security/pam_unix.so # unix (order 10900)

            auth sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass # unix (order 11600)
            password sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so nullok yescrypt # unix (order 10200)

            session required ${pkgs.linux-pam}/lib/security/pam_unix.so # unix (order 10200)
            session required ${pkgs.linux-pam}/lib/security/pam_loginuid.so # loginuid (order 10300)
          '';

          description = "PAM configuration to be written at {file}`/etc/pam.d/login.";
        };
      };
    };
  };

  config = mkIf config.security.pam.enable {
    environment.etc."pam.d/login".text = cfg.loginText;
  };
}
