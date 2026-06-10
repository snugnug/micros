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
            # Account management.
            account required pam_unix.so debug # unix (order 10900)

            # Authentication management.
            auth optional pam_unix.so debug likeauth nullok # unix-early (order 11500)
            auth sufficient pam_unix.so debug likeauth nullok try_first_pass # unix (order 12800)
            auth required pam_deny.so # deny (order 13600)

            # Password management.
            password sufficient pam_unix.so debug nullok yescrypt # unix (order 10200)

            # Session management.
            session required pam_unix.so debug # unix (order 10200)
            session required pam_loginuid.so # loginuid (order 10300)
          '';

          description = "PAM configuration to be written at {file}`/etc/pam.d/login.";
        };
      };
    };
  };

  config = mkIf config.security.pam.enable {
    security.wrappers = {
      unix_chkpwd = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${pkgs.linux-pam}/bin/unix_chkpwd";
      };
    };
    environment.systemPackages = [pkgs.linux-pam];
    environment.etc."pam.d/other".text = ''
      auth     required pam_warn.so
      auth     required pam_deny.so
      account  required pam_warn.so
      account  required pam_deny.so
      password required pam_warn.so
      password required pam_deny.so
      session  required pam_warn.so
      session  required pam_deny.so
    '';
    environment.etc."pam.d/passwd".text = ''
      account  required   pam_unix.so
      auth     sufficient pam_unix.so likeauth try_first_pass
      auth     required   pam_deny.so
      password sufficient pam_unix.so nullok yescrypt
    '';
    environment.etc."pam.d/login".text = cfg.loginText;
  };
}
