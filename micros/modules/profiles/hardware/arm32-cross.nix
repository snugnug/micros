{
  # Manually overlay packages that fail to cross-build on others systems.
  # This file must be imported manually, it is not necessary on hosts
  # that are running x86_64-linux.
  nixpkgs.overlays = [
    (_: prev: {
      libuv = prev.libuv.overrideAttrs (old: {
        doCheck = false;
      });
      elfutils = prev.elfutils.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
      });

      systemd = prev.systemd.override {withEfi = false;};
      util-linux = prev.util-linux.override {systemdSupport = false;};
      nix = prev.nix.override {enableDocumentation = false;};

      gnutls = prev.gnutls.overrideAttrs {doCheck = false;};
      graphite2 = prev.graphite2.overrideAttrs {doCheck = false;};
    })
  ];
}
