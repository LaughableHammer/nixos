{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    kitty
    vscode-fhs
    thunar
    thunar-volman
    gvfs
    vesktop
    thunderbird
    spotify
    xfce.xfconf
  ];

  # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    
    extraConfig = builtins.readFile ./hl.lua;
  };

  # Hyprcursor
  home.file.".local/share/icons/Future-Cyan-Hyprcursor_Theme".source =
    let
      hyprCursorRepo = pkgs.fetchgit {
        url = "https://gitlab.com/Pummelfisch/future-cyan-hyprcursor.git";
        rev = "cf4126d17f4520aceb688d8a60daca4a1f0b9e80";
        hash = "sha256-a7LdP2VH0UlMPwW9vbBolOuPQMJa0WNpmJfLLv3JZ4g=";
      };
    in
    pkgs.runCommand "hypr-cursor-cyan" { } ''
      ln -s ${hyprCursorRepo}/Future-Cyan-Hyprcursor_Theme $out
    '';

  # Noctalia Shell
  programs.noctalia = {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
      wallpaper = {
        enabled = true;
        default.path = "/path/to/wallpapers/wallpaper.png";
      };
    };
  };

  xfconf.enable = true;
  xfconf.settings."thunar-volman" = {
    "autobrowse/enabled" = false;
    "automount-drives/enabled" = false;
    "automount-media/enabled" = false;
    "autoopen/enabled" = false;
    "autorun/enabled" = false;
  };

  programs.firefoxpwa = {
    enable = true;
    settings = {
      "global.show_update_notifications" = true;
    };
    profiles."01ARZ3NDEKTSV4RRFFQ69G5FAV" = {
      name = "default";
      sites."01BX5ZZKBKACTAV9WEVGEMMVRZ" = {
        name = "Notion";
        url = "https://app.notion.com";
        manifestUrl = "https://www.notion.so/path/to/manifest.json"; # from step above
        desktopEntry.icon = pkgs.fetchurl {
          url = "https://upload.wikimedia.org/wikipedia/commons/4/45/Notion_app_logo.png";
          sha256 = "sha256-2oAdZZ2JFjIODXbIxiFU6XodRPcXYvKhjRyMGFYk1b4=";
        };
      };
    };
  };
}

