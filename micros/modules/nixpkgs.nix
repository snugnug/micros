{nixos-core, ...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      dhcpcd = prev.dhcpcd.override {withUdev = false;};
      procps = prev.procps.override {withSystemd = false;};
      pcslite = prev.pcslite.override {systemdSupport = false;};
      openssh = prev.openssh.override {withFIDO = false;};
      util-linux = prev.util-linux.override {
        systemdSupport = false;
      };
      ifupdown-ng = prev.callPackage ../../pkgs/ifupdown-ng.nix {};
      ifupdown-ng-minimal = prev.callPackage ../../pkgs/ifupdown-ng.nix {isMinimal = true;};
      nixos-core = nixos-core.packages.${prev.stdenv.system}.default.override {
        rustPlatform =
          if prev.stdenv.hostPlatform.isMusl
          then prev.pkgsMusl.rustPlatform
          else prev.rustPlatform;
      };
    })
  ];
}
