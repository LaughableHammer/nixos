{ inputs, pkgs, ... }:

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

  my.noctalia.sessionActions = [
    {
      action = "command";
      command = "systemctl start reboot-to-windows.service";
      countdown_seconds = 5.0;
      enabled = true;
      glyph = "brand-windows";
      label = "Restart to Windows";
      shortcut = "6";
      variant = "primary";
    }
  ];

  # Before first launch: `nix shell nixpkgs#legendary-gl` `legendary auth`
  home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rocket-league
  ];
}
