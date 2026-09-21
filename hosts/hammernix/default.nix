{ userName, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./reboot-to-windows.nix
    ../../modules/nixos/software/system-tools.nix
    ../../modules/nixos/software/desktop.nix
    ../../modules/nixos/software/virtualisation.nix
    ../../modules/nixos/software/secure-boot-tools.nix
  ];

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

  programs.gamemode.enable = true;
  users.users.${userName}.extraGroups = [ "gamemode" ];

  # Printing and automatic printer discovery
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

}
