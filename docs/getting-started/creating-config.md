# Starting a configuration

Micros images are configured using the nix language. To start a micros
configuration, create a folder and run
`nix flake init -t github:snugnug/micros`. This creates a nix flake with a basic
micros configuration, with the files `flake.nix`, `configuration.nix` and
`hardware-configuration.nix`. Below are explanations of the three files.

Note: when modifying the flake, the names and structure of the files (outside of
the `flake.nix` file) is unimportant, as long as the correct paths are included
in the list of modules. Additionally, if git is being used in the configuration
(which is recommended for configurations intended to be maintained and used over
long periods), files which are not tracked by git will not be included in the
system, and adding new files requires running `git add <file>` to track it in
git.

## Flake.nix file

The `flake.nix` file includes the following content.

```nix
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
```

The inputs define git repos which are included into the flake. The basic
configuration includes the 2 inputs, `nixpkgs` and `micros`. `nixpkgs` is the
standard nix repository, which includes the majority of packages used by micros,
along with extra functions which extend the nix language. `micros` includes all
of the packages and functions which are used specifically by the micros distro.
For the micros input, `input.nixpkgs.follows` tells the flake to use the user's
version of `nixpkgs`, not the default one used by the `micros` flake. This
ensures that package mismatches do not occur.

The outputs define the packages which the flake creates. The section
`{nixpkgs, micros, ...} @ inputs:` tells the flake to pass the inputs into the
packages, including them in the final built package.
`packages.x86_64-linux.default` defines the image built by `nix build`, and
`packages.x86_64-linux.container` defines the image built by
`nix build .#container`. `micros.lib.microsSystem` is the function which creates
the image, which includes 2 arguments. `modules` are the nix modules which are
included into the final configuration. This can be in the form of files which
include nix code, or nix code embedded directly. `specialArgs` defines the
arguments passed into the modules. `config.system.build.image` is the specific
output of a built `micros.lib.microsSystem` which includes an ISO image of the
distro. Alternatively, if building a container, this can be replaced with
`config.system.build.ociImage`, which creates an OCI-compatible image which can
be imported into docker or any other LXC runtime. `nixpkgs.hostPlatform` defines
the platform the image and its packages is intended to run on. This has a few
available options, including "x86_64-linux", "x86_64-unknown-linux-musl",
"aarch64-linux", and "armv7l-linux". Testing is primarily done on "x86_64-linux"
for ISO images and "x86_64-unknown-linux-musl" for OCI images.
`boot.isContainer = true` tells the micros builder to exclude kernel modules in
the final image, and skip various kernel initialisation steps.

## Configuration.nix file

The `configuration.nix` file defines the options set to generate the image. This
includes:

- Installed programs (both system-wide and user-wide)
- Users
- Services

The default content of the file is the following:

```nix
{
  pkgs,
  lib,
  ...
}: {
  # Enable the Getty login manager on the default terminal /dev/ttyS0
  services.getty.enable = true;

  users = {
    micros = {
      uid = 1000;
      gid = 1000;
      password = ""; # Blank password denotes passwordless login is allowed, use "!" (default) to disable password login entirely. To set a password, set this string to a hashed password using the `mkpasswd` command.
      packages = [
        pkgs.vim
        pkgs.ssh
      ]; # User-wide packages
    };
  };

  # Add a custom service
  micros.services = {
    custom-service = {
      startOnBoot = true; # Start the service with the rest of a system
      type = "oneshot"; # Do not restart the service after it stops
      startScript = ''
        #!${pkgs.busybox}/bin/ash

        exec ${pkgs.hello}
      ''; # Run a basic hello world program.
    };
  };

  environment.systemPackages = [
    pkgs.curl
  ]; # System-wide packages

  networking.firewall.enable = true;
  networking.nftables.enable = true;
}
```

This file has a few key sections.`{pkgs, lib, ...}` defines the external
variables passed into the file. This includes `pkgs`, which includes the
packages given by `micros` and `nixpkgs`, and `lib`, which includes the
functions given by `nixpkgs` and `micros`. All of the following options can be
found in more detail in the micros documentation. `services.getty.enable = true`
enables a pre-defined micros service. The `users` set defines a new user, the
`micros` user, gives it a UID and GID, sets the password as blank, and gives it
the `ssh` and `vim` packages. The `micros.services` set defines a custom service
which runs a hello world program on boot. `environment.systemPackages` defines a
list of packages which are installed system-wide. Finally,
`networking.firewall.enable` and `networking.nftables.enable` enable the network
firewalling. This is only a subset of the available options, and more can be
found in the micros options documentation.

## Hardware-configuration.nix file

The `hardware-configuration.nix` file sets the options for:

- Kernel configuration
- Filesystem mounting
- Drivers and firmware

The default configuration is:

```nix
{...}: {
  boot.initrd.kernelModules = [
    # SATA/PATA support.
    "ahci"

    "ata_piix"

    "sata_inic162x"
    "sata_nv"
    "sata_mv"
    "sata_promise"
    "sata_qstor"
    "sata_sil"
    "sata_sil24"
    "sata_sis"
    "sata_svw"
    "sata_sx4"
    "sata_uli"
    "sata_via"
    "sata_vsc"
    # omitted the rest of the list for conciseness
  ];
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    neededForBoot = true;
  };
  fileSystems."/iso" = {
    device = "/dev/disk/by-label/micros";
    fsType = "iso9660";
    options = ["ro"];
    neededForBoot = true;
  };
  fileSystems."/nix/store" = {
    device = "/mnt-root/iso/root.squashfs";
    fsType = "squashfs";
    options = ["ro"];
    neededForBoot = true;
  };
  networking.interfaces = [
    {
      name = "eth0";
    }
  ];
}
```

This file defines the kernel modules loaded on boot, the root filesystem, ISO
mounting, and nix store mounting. It also defines the network interfaces used by
the image. This file should not be included in container images, as these
options are handled by the container runtime.
