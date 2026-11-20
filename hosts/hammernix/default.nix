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
    ../../modules/nixos/ai/open-webui.nix
  ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.limine = {
    enable = true;
    # Let the installer create/maintain the "Limine" NVRAM entry for the ESP that
    # holds /boot. The removable fallback (\EFI\BOOT\BOOTX64.EFI) is ambiguous
    # once both disks have an ESP, so it must not be what selects the disk.
    efiInstallAsRemovable = false;
    enrollConfig = true;
    maxGenerations = 10;
    secureBoot.enable = true;

    # Windows goes on the 500GB disk, so once it is installed bootmgfw.efi lives
    # on THAT disk's ESP, not on this one: boot() resolves to the ESP holding
    # this config. Replace boot() with the FAT serial of the Windows ESP once it
    # exists (`lsblk -o NAME,FSTYPE,UUID /dev/nvme1n1p1`), e.g.
    #   path: guid(1A2B-3C4D):/EFI/Microsoft/Boot/bootmgfw.efi
    extraEntries = ''
      /Windows 11
      protocol: efi
      path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;
  users.users.${userName}.extraGroups = [
    "gamemode"
    "deepcool-digital"
  ];

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

  # Local name for the Open WebUI service on 127.0.0.1:8081.
  networking.hosts."127.0.0.1" = [ "openwebui.local" ];

  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

}
