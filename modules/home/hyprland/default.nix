{ lib, ... }:

{
  options.my.hyprland.hostConfigFiles = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = "Host-specific Hyprland configuration fragments.";
  };
}
