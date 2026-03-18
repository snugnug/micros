{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../virtualisation/lxc-container.nix
  ];
}
