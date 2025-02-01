{
  environment.etc = {
    "sv/getty-5/run".text = ''
      #!/bin/sh
      exec /sbin/getty 38400 tty5 linux
    '';

    "sv/getty-5/finish".text = ''
      #!/bin/sh
      exec utmpset -w tty5
    '';
  };
}
