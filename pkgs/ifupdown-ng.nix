{
  fetchFromGitHub,
  stdenv,
  libbsd,
  iproute2,
  ...
}:
stdenv.mkDerivation {
  pname = "ifupdown-ng";
  version = "0-unstable-2025-05-31";

  src = fetchFromGitHub {
    owner = "ifupdown-ng";
    repo = "ifupdown-ng";
    rev = "e305296b3d23e56bba92c504e030d8e4b91db403";
    hash = "sha256-psA7HxDS9asUan7wKVeWB9fbL+da+s49wRvTqRQnwP0=";
  };
  buildInputs = [libbsd iproute2];
  patches = [
    ./ifupdown-fix-path.patch
  ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ${builtins.concatStringsSep "\n" (map (x: "install -D -m755 ${x} $out/bin") ["ifupdown" "ifup" "ifdown" "ifquery" "ifparse" "ifctrstat"])}
    mkdir -p $out/usr/libexec/ifupdown-ng
    install -D -m755 executor-scripts/linux/* $out/usr/libexec/ifupdown-ng/
    runHook postInstall
  '';
}
