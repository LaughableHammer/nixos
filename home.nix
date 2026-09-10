{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    inputs.noctalia.homeModules.default
    ./modules/home/hyprland
  ];
  home.stateVersion = "26.05";

  # Concatenate the Hyprland configuration fragments
  home.file.".config/hypr/hyprland.lua".text =
    builtins.concatStringsSep "\n" (
      map builtins.readFile (
        [
          ./hyprland/autostart.lua
          ./hyprland/appearance.lua
        ]
        ++ config.my.hyprland.hostConfigFiles
        ++ [
          ./hyprland/window-rules.lua
          ./hyprland/keybinds-noctalia.lua
          ./hyprland/keybinds-applications.lua
          ./hyprland/keybinds-windows.lua
          ./hyprland/keybinds-workspaces.lua
          ./hyprland/keybinds-media.lua
          ./hyprland/input.lua
          ./hyprland/cursor.lua
          ./hyprland/keybinds-screenshots.lua
        ]
      )
    );

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
    settings = ./noctalia-base.toml;
  };

  # Keep GUI-managed overrides writable and versioned in this repository.
  home.file.".local/state/noctalia/settings.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/noctalia-gui-overrides.toml";
    force = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
  };

  dconf.enable = true;
  # GTK4/libadwaita apps (most modern GNOME apps) also check this portal setting
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
  };

  # Otherwise links don't properly open in firefox
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };
}
