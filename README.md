# MicrOS

MicrOS is a small, experimental operating system designed for embedded
situations. It is based heavily on NixOS, but compiles down to a microscopic
kernel[^1], an initrd and a ~50mb squashfs.

[Runit](https://smarden.org/runit/) is used instead of systemd, with some degree
of abstraction over services. This is not as robust as NixOS systemd module, nor
is it in any way portable (i.e., additional init systems are not yet possible)
but it results in a small and fast image for low-resource scenarios, e.g.,
embedded development.

## Why

NixOS is great, it fits under most use-cases and it is extremely flexible on
what you might use it for. Unfortunately for us, it is quite _large_ even after
you go out of your way to "debloat" it by applying various overlays that create
a butterfly effect in the module system, breaking things you did not even know
were called by your system. This is not unexpected, as Nixpkgs is quite large,
but it is also very annoying.

MicrOS aims to be a robust solution to building small, minimal, _and functional_
systems for various use cases. More specifically, embedded Linux and
containerization.

## Building

Micros is a build system more so than it is a collection of hardware modules. It
should be utilized _primarily_ as a module system to reduce friction in building
images for embedded systems.

Construct your own system with `lib.microsSystem`. This functions almost
identical to `lib.nixosSystem` that you might be familiar with.

```nix
lib.microsSystem {
  modules = [
    {
      not-os.rpi1 = true;
      not-os.rpi2 = true;

      system.build.rpi-firmware = raspi-firmware;

      nixpkgs.hostPlatform = {system = "armv7l-linux";};
      nixpkgs.buildPlatform = {system = "x86_64-linux";};

    }
  ];
};
```

Above configuration enough to construct a basic system. You may build different
components of the configuration, available under `config.system.build` to create
different build artifacts for different workflows.

## Contributing

Contributions are always welcome. If you have anything you'd like to see
implemented, and would like to work on implementing it then please create an
issue so that we may figure out next. Please remember to write comments in
particularly complex areas if adding new modules, or refactoring existing
modules.

You may visit [runit/runscripts](https://smarden.org/runit/runscripts) for
additional services that could be upstreamed to MicrOS.

## License

[not-os]: https://github.com/cleverca22/not-os

> [!NOTE]
> Work here is based _heavily_ on the awesome [not-os]. I worked on something
> similar until I realized I was duplicating effort for no reason. This
> repository diverges (and will continue to diverge from not-os) in terms of
> module structure, coding conventions and goals on what should and should not
> be provided. In addition to the aggressive repository restructure, I will be
> working to provide more _idiomatic_ Nix code that follows best practices and
> focuses on purity.

MicrOS is a _soft_-fork of not-os, plain and simple. Any and all work here is
available under the MIT license, following upstream. I do not make any claims on
the code provided here. Please support the original author and contributors.

The nature of MicrOS does not quite allow for a dependency on nixpkgs due to its
tight integration with systemd. Although, we borrow modules from nixpkgs at
times to avoid duplicating work, or to avoid reinventing the wheel as as square.
A copyright notice is hereby provided that _some_ modules in MicrOS are directly
copied from nixpkgs, also available under the MIT license.

Please see [LICENSE](LICENSE.md) for details.

[^1]: For the time being MicrOS attempts to boot the mainline kernel as
    development is most steadily pacing on `x86_64-linux` and we would like
    minimum amount of rebuilds possible. In the future, likely after there is
    some CI infrastructure, alternative kernels aiming at achieving smaller
    kernels might become a priority.
