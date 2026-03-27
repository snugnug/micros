{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.isContainer = true;
  networking.timeServers = [];
}
