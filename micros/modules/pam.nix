{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption types mkIf;
in {
  options = {
    security = {
      pam = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
      };
    };
  };
  config = mkIf config.security.pam.enable {
    environment.etc."pam.d/login".text = ''
      account required ${pkgs.linux-pam}/lib/security/pam_unix.so # unix (order 10900)

      auth sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass # unix (order 11600)
      password sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so nullok yescrypt # unix (order 10200)

      session required ${pkgs.linux-pam}/lib/security/pam_unix.so # unix (order 10200)
      session required ${pkgs.linux-pam}/lib/security/pam_loginuid.so # loginuid (order 10300)
    '';
  };
}
