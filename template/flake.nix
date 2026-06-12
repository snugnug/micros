{
  inputs = {
    micros = {
      url = "github:snugnug/micros";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = {
    nixpkgs,
    micros,
    ...
  } @ inputs: {
    packages.x86_64-linux.default =
      (micros.lib.microsSystem {
        specialArgs = {inherit inputs;};
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix

          {
            nixpkgs.hostPlatform = {
              system = "x86_64-linux";
            };
          }
        ];
      }).config.system.build.image;
    packages.x86_64-linux.container =
      (micros.lib.microsSystem {
        specialArgs = {inherit inputs;};
        modules = [
          ./configuration.nix

          {
            boot.isContainer = true;
            nixpkgs.hostPlatform = {
              system = "x86_64-unknown-linux-musl";
            };
          }
        ];
      }).config.system.build.ociImage;
  };
}
