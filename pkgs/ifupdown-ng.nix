{
  fetchFromGitHub,
  stdenv,
  libbsd,
  iproute2,
  libmnl,
  pkg-config,
  isMinimal ? false,
  busybox,
  lib,
  ...
}:
stdenv.mkDerivation {
  pname = "ifupdown-ng" + lib.optionalString isMinimal "-minimal";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "ifupdown-ng";
    repo = "ifupdown-ng";
    rev = "60777d0f33453335761e8ab94359e6b31a4c8c1a";
    hash = "sha256-+M8c59LjJlO1Vdl+Lo5EXjMEaHWemGWvBsDw/MaY/IE=";
  };
  nativeBuildInputs = [pkg-config libmnl];
  buildInputs = [libbsd] ++ lib.optionals isMinimal [iproute2];
  patches = [
    ./ifupdown-fix-path.patch
  ];
  buildPhase = ''
    make LIBBSD_CFLAGS="$(pkg-config --cflags libbsd-overlay)" LIBBSD_LIBS="$(pkg-config --cflags --libs libbsd-overlay)"
  '';
  installPhase = let
    minimalExecutors = ["bond" "bridge" "dhcp" "forward" "ipv6" "ipv6-ra" "ipv6-tempaddr" "link" "static"];
  in ''
    runHook preInstall
    mkdir -p $out/bin
    ${builtins.concatStringsSep "\n" (map (x: "install -D -m755 ${x} $out/bin") ["ifupdown" "ifup" "ifdown" "ifquery" "ifparse" "ifctrstat"])}
    mkdir -p $out/usr/libexec/ifupdown-ng
    ${
      if isMinimal
      then (builtins.concatStringsSep "\n" (map (x: "install -D -m755 executors/linux/${x} $out/usr/libexec/ifupdown-ng") minimalExecutors))
      else "install -D -m755 executors/linux/* $out/usr/libexec/ifupdown-ng"
    }
    runHook postInstall
  '';
}
