{ ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.limine = {
    enable = true;
    efiInstallAsRemovable = true;
    enrollConfig = true;
    maxGenerations = 10;
    secureBoot.enable = true;

    extraEntries = ''
      /Windows 11
      protocol: efi
      path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
