{ userName, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./reboot-to-windows.nix
    ../../modules/nixos/software/system-tools.nix
    ../../modules/nixos/software/desktop.nix
    ../../modules/nixos/software/virtualisation.nix
    ../../modules/nixos/software/secure-boot-tools.nix
    ../../modules/nixos/ai
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
  users.users.${userName}.extraGroups = [ "gamemode" "deepcool-digital" ];

  # The CH360 Digital display is a USB HID device (3633:0015).
  services.hardware.deepcool-digital-linux.enable = true;
  users.groups.deepcool-digital = { };
  services.udev.extraRules = ''
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", ATTRS{idProduct}=="0015", GROUP="deepcool-digital", MODE="0660"
  '';
  systemd.services.deepcool-digital-linux.serviceConfig = {
    User = userName;
    # The AMD GPU hwmon sensor can appear after this service first starts.
    RestartSec = "5s";
  };

  # Printing and automatic printer discovery
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

}
