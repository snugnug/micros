{pkgs, ...}: {
  imports = [./qemu.nix];
  not-os.nix = true;
  environment.systemPackages = [pkgs.utillinux];
  environment.etc = {
    "ssh/authorized_keys.d/root" = {
      text = "";
      mode = "0444";
    };
  };
}
