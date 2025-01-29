# MicrOS

[not-os]: https://github.com/cleverca22/not-os

MicrOS is a small, experimental operating system designed for embedded
situations. It is based heavily on NixOS, but compiles down to a microscopic
kernel, an initrd and a 48mb squashfs.

[Runit](https://smarden.org/runit/) is used instead of system, with some degree
of abstraction over services. This is not as robust as NixOS systemd module, nor
is it in any way portable (i.e., additional init systems are not yet possible)
but it results in a small and fast image for low-resource scenarios, e.g.,
embedded development.

> [!NOTE]
> Work here is based _heavily_ on the awesome [not-os]. I worked on something
> similar until I realized I was duplicating effort for no reason. This
> repository diverges (and will continue to diverge from not-os) in terms of
> module structure, coding conventions and goals on what should and should not
> be provided. In addition to the aggressive repository restructure, I will be
> working to provide more _idiomatic_ Nix code that follows best practices and
> focuses on purity.

## License

MicrOS is a _soft_-fork of not-os, plain and simple. Any and all work here is
available under the MIT license, following upstream. I do not make any claims on
the code provided here. Please support the original author and contributors.
