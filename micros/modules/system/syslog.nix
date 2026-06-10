{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib) types;
in {
  options = {
    system.logging = {
      enable = mkEnableOption "Enable syslog daemon" // {default = true;};
      syslogPackage = mkOption {
        type = types.oneOf [types.str types.package];
        default = "${pkgs.sysklogd}/bin/syslogd";
        description = ''
          Syslog daemon to use for system logging. Defaults to busybox's syslog implementation. If the option is set to a derivation, lib.getExe is used to get the executable file. If the option is set to a string, it is executed directly.
        '';
      };
      syslogFlags = mkOption {
        type = types.str;
        default = "-F -p /dev/log";
        description = ''
          Flags passed to syslog executable.
        '';
      };
      syslogConfig = mkOption {
        type = types.lines;
        default = ''
          # /etc/syslog.conf - Configuration file for syslogd(8)
          #
          # For information about the format of this file, see syslog.conf(5)
          #

          #
          # First some standard log files.  Log by facility.
          #
          auth,authpriv.*			 /var/log/auth.log
          *.*;auth,authpriv.none		-/var/log/syslog

          #cron.*				/var/log/cron.log
          #daemon.*			-/var/log/daemon.log
          kern.*				-/var/log/kern.log
          #lpr.*				-/var/log/lpr.log
          mail.*				-/var/log/mail.log
          #user.*				-/var/log/user.log

          #
          # Logging for the mail system.  Split it up so that
          # it is easy to write scripts to parse these files.
          #
          #mail.info			-/var/log/mail.info
          #mail.warn			-/var/log/mail.warn
          mail.err			 /var/log/mail.err
          #mail.*;mail.!=info		-/var/log/mail
          #mail,news.=info 		-/var/log/info

          # The tcp wrapper loggs with mail.info, we display all
          # the connections on tty12
          #
          #mail.=info			/dev/tty12

          #
          # Some "catch-all" log files.
          #
          #*.=debug;\
          #	auth,authpriv.none;\
          #	news.none;mail.none	-/var/log/debug
          *.=info;*.=notice;*.=warn;\
          	auth,authpriv.none;\
          	cron,daemon.none;\
          	mail,news.none		-/var/log/messages

          #
          # Store all critical events, except kernel logs, in critical RFC5424 format.
          # Override global log rotation settings, rotate every 10MiB, keep 5 old logs,
          #
          #*.=crit;kern.none		/var/log/critical	;rotate=10M:5,RFC5424

          # Example of sending events to remote syslog server.
          # All events from notice and above, except auth, authpriv
          # and any kernel message are sent to server finlandia in
          # RFC5424 formatted output.
          #
          #*.notice;auth,authpriv.none;\
          #	kern.none		@finlandia	;RFC5424

          # Emergencies are sent to anyone logged in
          #
          *.=emerg			*

          # Priority alert and above are sent to the operator
          #
          #*.alert			root,joey

          #
          # Secure mode, same as -s, none(0), on(1), full(2).  When enabled
          # only logging to remote syslog server possible, with full secure
          # mode, not even that is possible.  We default to prevent syslogd
          # from opening UDP/514 and receiving messages from other systems.
          #
          secure_mode 1

          #
          # Global log rotation, same as -r SIZE:COUNT, command line wins.
          #
          #rotate_size  1M
          #rotate_count 5

          #
          # Include all config files in /etc/syslog.d/
          #
          include /etc/syslog.d/*.conf
        '';
        description = ''
          Contents of /etc/syslog.conf file
        '';
      };
    };
  };
  config = lib.mkIf config.system.logging.enable {
    environment.etc = {
      "syslog.conf".text = config.system.logging.syslogConfig;
    };
    micros.services.syslog = {
      startOnBoot = true;
      type = "oneshot";
      enable = true;
      startScript = ''
        #!${pkgs.busybox}/bin/ash
        mkdir /var/log

        ${
          if (lib.isStorePath config.system.logging.syslogPackage || lib.isDerivation config.system.logging.syslogPackage)
          then "${lib.getExe config.system.logging.syslogPackage}"
          else "${config.system.logging.syslogPackage}"
        } ${config.system.logging.syslogFlags}
      '';
    };
  };
}
