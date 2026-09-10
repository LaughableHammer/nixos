{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.noctalia.homeModules.default ];
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    # JavaScript / TypeScript
    nodejs_22
    typescript
    typescript-language-server
    eslint
    prettier
    pnpm

    # C / C++
    gcc
    clang-tools
    gnumake
    cmake
    ninja
    gdb
    lldb
    pkg-config

    # Python
    python3
    uv

    # General development tools
    git
    ripgrep
    fd
    jq
    shellcheck
    shfmt
    nixd
    nixfmt

    # Desktop applications
    kitty
    vesktop
    spotify
    xfconf
    swayimg
    proton-vpn
    satty
    libreoffice
    nomacs
    slack
    mpv
  ];

  # Use the normal VS Code package. Keep extensions mutable so the extensions
  # already installed in ~/.vscode/extensions remain available.
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = true;
    profiles.default.extensions =
      with pkgs.vscode-extensions;
      [
        # JavaScript / TypeScript and web development
        bradlc.vscode-tailwindcss
        dbaeumer.vscode-eslint
        ecmel.vscode-html-css
        esbenp.prettier-vscode

        # C / C++
        llvm-vs-code-extensions.vscode-clangd
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        ms-vscode.makefile-tools

        # Common formats and project tooling
        editorconfig.editorconfig
        github.vscode-github-actions
        jnoortheen.nix-ide
        redhat.vscode-yaml
        tamasfe.even-better-toml
      ]
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          # Current theme: "Celestial Echoes"
          publisher = "jemo";
          name = "celestial-echoes";
          version = "0.0.7";
          hash = "sha256-cccCmXUUMhMI8fzehgzYfewwwWEyDlWu3bHsurdNV0A=";
        }
      ];
  };

  programs.thunderbird = {
    enable = true;
    policies.Preferences."mail.shell.checkDefaultClient" = {
      Value = false;
      Status = "locked";
    };
  };

  # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    # Concatenate the Hyprland Lua modules in a predictable order.
    extraConfig = builtins.concatStringsSep "\n" (
      map builtins.readFile [
        ./hyprland/autostart.lua
        ./hyprland/appearance.lua
        ./hyprland/monitors.lua
        ./hyprland/workspaces.lua
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
    );
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
    settings = ./noctalia-base.toml;
  };

  # Keep GUI-managed overrides writable and versioned in this repository.
  home.file.".local/state/noctalia/settings.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/noctalia-gui-overrides.toml";
    force = true;
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
