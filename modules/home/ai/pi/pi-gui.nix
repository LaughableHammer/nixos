{ pkgs, ... }:

let
  pname = "pi-gui";
  version = "1.0.1";

  # Upstream ships official Linux builds; the AppImage is wrapped in an FHS
  # environment so Electron and its bundled libraries work on NixOS.
  src = pkgs.fetchurl {
    url = "https://github.com/minghinmatthewlam/pi-gui/releases/download/v${version}/pi-gui-${version}-x86_64.AppImage";
    hash = "sha256-WByWXZajwvDbPx6I6Ro8PRHxNT3TFYpXy+XLmJ1TdoE=";
  };

  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

  pi-gui = pkgs.appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      install -Dm644 \
        ${appimageContents}/pi-gui.desktop \
        $out/share/applications/pi-gui.desktop
      # Upstream's desktop entry launches AppRun; point it at the wrapper.
      substituteInPlace $out/share/applications/pi-gui.desktop \
        --replace-fail "Exec=AppRun" "Exec=${pname}"
      install -Dm644 \
        ${appimageContents}/usr/share/icons/hicolor/512x512/apps/pi-gui.png \
        $out/share/icons/hicolor/512x512/apps/pi-gui.png
    '';
  };
in
{
  home.packages = [ pi-gui ];
}
