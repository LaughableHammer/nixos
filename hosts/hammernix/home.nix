{ ... }:

{
  # These fragments describe this computer's physical display arrangement.
  _module.args.hostHyprlandConfig = [
    ./hyprland/monitors.lua
    ./hyprland/workspaces.lua
  ];
}
