{ ... }:

{
  imports = [
    ../../modules/home/software/development.nix
    ../../modules/home/software/desktop-apps.nix
  ];

  # These fragments describe this computer's physical display arrangement.
  my.hyprland.hostConfigFiles = [
    ./hyprland/monitors.lua
    ./hyprland/workspaces.lua
  ];
}
