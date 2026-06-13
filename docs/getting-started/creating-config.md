# Starting a MicrOS Configuration

MicrOS images are configured using the Nix language. To start a MicrOS
configuration, create a folder and run:

```bash
# Create a flake with the default MicrOS template
$ nix flake init -t github:snugnug/micros
```

This creates a Nix flake containing a MicrOS configuration, with the files
`flake.nix`, `configuration.nix` and `hardware-configuration.nix`. Below are
explanations of the three files.

> [!NOTE]
> When modifying the flake, the names and structure of the files (outside of the
> `flake.nix` file) is unimportant, as long as the correct paths are included in
> the list of modules. Additionally, if git is being used in the configuration
> (which is recommended for configurations intended to be maintained and used
> over long periods), files which are not tracked by git will not be included in
> the system, and adding new files requires running `git add <file>` to track it
> in git.

## `flake.nix`

[relevant NixOS Wiki page]: https://wiki.nixos.org/wiki/Flakes

> [!TIP]
> An explanation of Nix flakes, their schema, and common fields can be found on
> the [relevant NixOS Wiki page]. This guide assumes you are at least vaguely
> familiar with the concept of Nix flakes.

The `flake.nix`, i.e., your "configuration flake" typically includes the
following content:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    # The 'micros' input provides the custom library and module system
    # required to build a MicrOS system.
    micros = {
      url = "github:snugnug/micros";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

The inputs define your sources, which will get copied to the Nix store while the
flake is being evaluated. The basic/example configuration includes the 2 inputs:
`nixpkgs` and `micros`.

`nixpkgs` is the standard nix repository, which includes the majority of
packages used by MicrOS, along with extra functions which extend the Nix
language available under `nixpkgs.lib`. The `micros` input includes all of the
packages and functions which are used specifically by MicrOS. For the `micros`
input, `input.nixpkgs.follows` tells the flake to use the user's version of
`nixpkgs`, not the default one used by the `micros` flake. This ensures that
package mismatches do not occur, though, this might cause "cache misses" where a
divergence in the source invalidates caching.

In our case, outputs define the packages "exposed" by the flake. Typically
flakes can provide more than just packages but for our purposes only `packages`
are relevant. The argument set to the `outputs` section, e.g.,
`{nixpkgs, micros, ...} @ inputs:` deconstructs `inputs` to make `nixpkgs` and
`micros` inputs available individually instead of obtaining them through
`inputs.<input>` each time. The use of `specialArgs = {inherit inputs;}` will
pass the inputs reference into the MicrOS configuration, allowing you to
reference your inputs throughout files imported by `microsSystem`.

### Packages

The example configuration has two distinct packages:

- `packages.x86_64-linux.default` defines the image built by `nix build`,
- `packages.x86_64-linux.container` defines the image built by
  `nix build .#container`.

`micros.lib.microsSystem` is the function that creates the system reference,
which includes two arguments and exposes various derivations that we can use
with `nix build`. The `modules` argument contains the Nix modules imported,
i.e., included in the final configuration. This can be in the form of files
which include nix code, or nix code embedded directly. `specialArgs` defines the
arguments passed into the modules.

`config.system.build.image` is the specific output of a built
`micros.lib.microsSystem` which includes an ISO image of the distro.

Alternatively, if building a container, this can be replaced with
`config.system.build.ociImage`, which creates an OCI-compatible image, which can
be imported into docker or any other LXC runtime. `nixpkgs.hostPlatform` defines
the platform the image and its packages is intended to run on. This has a few
available options, including `"x86_64-linux"`, `"x86_64-unknown-linux-musl"`,
`"aarch64-linux"`, and `"armv7l-linux"`. Testing is primarily done on
`"x86_64-linux"` for ISO images, and `"x86_64-unknown-linux-musl"` for OCI
images. `boot.isContainer = true` tells the MicrOS builder to exclude kernel
modules in the final image, and skip various kernel initialisation steps.

## `configuration.nix`

The `configuration.nix` file defines the options set to generate the image. This
includes:

- Users
- Installed programs (both system-wide and user-wide via `user.packages` and
  `programs.*` or such)
- Services (`services.*`, `micros.services.*`, etc.)
- Additionally imported files via `imports = []`

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

      # Blank password denotes passwordless login is allowed, use "!" (default)
      # to disable password login entirely. To set a password, set this string
      # to a hashed password using the `mkpasswd` command.
      password = ""; 
      
      # User-wide packages
      packages = [
        pkgs.vim
        pkgs.ssh
      ];
    };
  };

  # Add a custom MicrOS service
  micros.services = {
    custom-service = {
      startOnBoot = true; # start the service with the rest of a system
      type = "oneshot"; # do not restart the service after it stops

      # Run a basic hello world program.
      startScript = ''
        #!${pkgs.busybox}/bin/ash

        exec ${pkgs.hello}/bin/hello
      ''; 
    };
  };

  # System-wide packages. Those are installed for all users.
  environment.systemPackages = [
    pkgs.curl
  ]; 

  networking.firewall.enable = true;
  networking.nftables.enable = true;
}
```

The `configuration.nix` file has a few key sections:

- `{pkgs, lib, ...}` is the "argument set", and has us pass the special
  arguments (remember `specialArgs`) defined by `microsSystem` to be passed down
  to files that are a part of the module system, i.e., the underlying
  `evalModules` call. This includes `pkgs`, which includes the packages given by
  `micros` and `nixpkgs`, and `lib`, which includes the functions given by
  `nixpkgs` and `micros`.
- An implicit `configuration` section, which is the main attribute set. Contains
  options like:
  - The `users` set, which defines a new user (the `micros` user), gives it a
    UID and GID, sets the password as blank, and gives it the `ssh` and `vim`
    packages.
  - The `micros.services` set defines a custom service, which runs a hello world
    program on boot.
  - `environment.systemPackages` defines a list of packages which are installed
    system-wide.
  - `networking.firewall.enable` and `networking.nftables.enable` enable the
    network firewalling.

  > [!NOTE]
  > This is only a subset of the available options, and more can be found in the
  > MicrOS options documentation.

## `hardware-configuration.nix`

`hardware-configuration.nix` is a conventional, but by no means a _necessary_
file that _typically_ sets the options for:

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
  
  networking.interfaces = [{
    name = "eth0";
  }];
}
```

This file defines the kernel modules loaded on boot, the root filesystem, ISO
mounting, and nix store mounting. It also defines the network interfaces used by
the image. This file should not be included in container images, as these
options are handled by the container runtime.

You may discard `hardware-configuration.nix` if you please, and simply insert
such options in other files that you wish to import. The contents of
`hardware-configuration.nix` could, for example, be moved to `configuration.nix`
or split into their own files like `kernel.nix`, `fs.nix`, `networking.nix`,
etc.
