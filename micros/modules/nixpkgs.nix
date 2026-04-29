{inputs, ...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      dhcpcd = prev.dhcpcd.override {withUdev = false;};
      procps = prev.procps.override {withSystemd = false;};
      pcslite = prev.pcslite.override {systemdSupport = false;};
      openssh = prev.openssh.override {withFIDO = false;};
      util-linux = prev.util-linux.override {
        systemd = null;
        systemdSupport = false;
      };
      ifupdown-ng = prev.callPackage ../../pkgs/ifupdown-ng.nix {};
      nixos-core = inputs.nixos-core.packages.${prev.stdenv.system}.default;
    })
  ];
}
