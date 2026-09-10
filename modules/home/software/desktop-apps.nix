{ pkgs, ... }:

{
  home.packages = with pkgs; [
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

  programs.thunderbird = {
    enable = true;
    policies.Preferences."mail.shell.checkDefaultClient" = {
      Value = false;
      Status = "locked";
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
        manifestUrl = "https://www.notion.so/path/to/manifest.json";
        desktopEntry.icon = pkgs.fetchurl {
          url = "https://upload.wikimedia.org/wikipedia/commons/4/45/Notion_app_logo.png";
          sha256 = "sha256-2oAdZZ2JFjIODXbIxiFU6XodRPcXYvKhjRyMGFYk1b4=";
        };
      };
    };
  };
}
