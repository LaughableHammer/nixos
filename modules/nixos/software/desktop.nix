{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    chromium
    file-roller
  ];

  programs.firefox.enable = true;
  # firefoxpwa is managed in home-manager (modules/home/software/desktop-apps.nix).

  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.tumbler.enable = true;
}
