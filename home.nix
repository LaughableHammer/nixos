{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    kitty
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    extraConfig = ''
-- ================================================================
-- Noctalia: autostart
-- ================================================================
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
  },
  decoration = {
    rounding = 20,
    rounding_power = 2,
    shadow = {
      enabled = true,
      range = 4,
      render_power = 3,
      color = 0xee1a1a1a,
    },
    blur = {
      enabled = true,
      size = 3,
      passes = 2,
      vibrancy = 0.1696,
    },
  },
})

-- ================================================================
-- Monitors
-- DP-2: main landscape panel, 2560x1440 @180Hz, sits at 0x0.
-- HDMI-A-1: secondary panel, rotated 90 clockwise (transform = 1),
-- placed to the right of DP-2 and centered on it vertically.
-- Native res is 1920x1080; rotated, its footprint is 1080 wide x 1920 tall,
-- so it's shifted up by (1920 - 1440) / 2 = 240px to center against DP-2.
-- ================================================================
hl.monitor({ output = "DP-2", mode = "2560x1440@180", position = "0x0", scale = 1.0 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "2560x-240", scale = 1.0, transform = 1 })

-- ================================================================
-- Noctalia: persistent workspaces
-- Primary workspaces live on DP-2; 6/7 are already active on
-- DP-2/HDMI-A-1 respectively per hyprctl monitors, left unpinned here.
-- ================================================================
hl.workspace_rule({ workspace = "1", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-2", persistent = true })

-- ================================================================
-- Noctalia: window / layer rules
-- ================================================================
hl.window_rule({
  match = { class = "dev.noctalia.Noctalia" },
  float = true,
  size = { 1080, 920 },
})

hl.layer_rule({
  name = "noctalia",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$",
  },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})

local modifier = "SUPER"

-- ================================================================
-- NOCTALIA KEYBINDS
-- ================================================================
hl.bind(modifier .. " + D", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Noctalia Launcher" })
hl.bind(modifier .. " + SHIFT + Return", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Noctalia Launcher" })
hl.bind(modifier .. " + M", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center notifications"), { description = "Noctalia Notifications" })
hl.bind(modifier .. " + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"), { description = "Noctalia Clipboard" })
hl.bind(modifier .. " + ALT + P", hl.dsp.exec_cmd("noctalia msg settings-toggle"), { description = "Noctalia Settings" })
hl.bind(modifier .. " + SHIFT + comma", hl.dsp.exec_cmd("noctalia msg settings-toggle"), { description = "Noctalia Settings" })
hl.bind(modifier .. " + CTRL + L", hl.dsp.exec_cmd("noctalia msg session lock"), { description = "Noctalia Lock Screen" })
hl.bind(modifier .. " + SHIFT + W", hl.dsp.exec_cmd("noctalia msg panel-toggle wallpaper"), { description = "Noctalia Wallpaper" })
hl.bind(modifier .. " + X", hl.dsp.exec_cmd("noctalia msg panel-toggle session"), { description = "Noctalia Power Menu" })
hl.bind(modifier .. " + C", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"), { description = "Noctalia Control Center" })
hl.bind(modifier .. " + CTRL + R", hl.dsp.exec_cmd("noctalia msg screenshot-region"), { description = "Noctalia Screenshot Region" })
hl.bind(modifier .. " + SHIFT + R", hl.dsp.exec_cmd("restart.noctalia"), { description = "Restart Noctalia Shell" })
hl.bind(modifier .. " + Space", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Noctalia Launcher (Space)" })

-- ================================================================
-- WORKSPACE OVERVIEW
-- ================================================================
hl.bind(modifier .. " + CTRL + D", hl.dsp.exec_cmd("dock"), { description = "Toggle Dock" })
hl.bind(modifier .. " + Tab", hl.dsp.exec_cmd("qs ipc -c overview call overview toggle"), { description = "QS Overview" })

-- ================================================================
-- TERMINALS
-- ================================================================
hl.bind(modifier .. " + Return", hl.dsp.exec_cmd("kitty"), { description = "Terminal" })

-- ================================================================
-- APPLICATION LAUNCHERS
-- ================================================================
hl.bind(modifier .. " + K", hl.dsp.exec_cmd("qs-keybinds"), { description = "Keybinds Search Tool" })
hl.bind(modifier .. " + CTRL + C", hl.dsp.exec_cmd("qs-cheatsheets"), { description = "Cheatsheets Viewer" })
hl.bind(modifier .. " + SHIFT + K", hl.dsp.exec_cmd("qs-keybinds"), { description = "Keybinds Search Tool" })
hl.bind(modifier .. " + SHIFT + D", hl.dsp.exec_cmd("discord"), { description = "Discord" })
hl.bind(modifier .. " + ALT + W", hl.dsp.exec_cmd("web-search"), { description = "Web Search" })
hl.bind(modifier .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -rs"), { description = "Notification Reset" })
hl.bind(modifier .. " + W", hl.dsp.exec_cmd("firefox"), { description = "Web Browser" })
hl.bind(modifier .. " + Y", hl.dsp.exec_cmd("kitty -e yazi"), { description = "File Manager" })
hl.bind(modifier .. " + E", hl.dsp.exec_cmd("emopicker9000"), { description = "Emoji Picker" })
hl.bind(modifier .. " + S", hl.dsp.exec_cmd("screenshootin"), { description = "Screenshot" })

-- ================================================================
-- SCREENSHOTS
-- ================================================================
hl.bind(modifier .. " + CTRL + S", hl.dsp.exec_cmd("hyprshot -m output -o $HOME/Pictures/ScreenShots"), { description = "Screenshot Output" })
hl.bind(modifier .. " + ALT + S", hl.dsp.exec_cmd("hyprshot -m region -o $HOME/Pictures/ScreenShots"), { description = "Screenshot Region" })
hl.bind(modifier .. " + O", hl.dsp.exec_cmd("obs"), { description = "OBS Studio" })
hl.bind(modifier .. " + ALT + C", hl.dsp.exec_cmd("hyprpicker -a"), { description = "Color Picker" })
hl.bind(modifier .. " + G", hl.dsp.exec_cmd("gimp"), { description = "GIMP" })
hl.bind(modifier .. " + SHIFT + T", hl.dsp.exec_cmd("sh -lc 'DropTerminal'"), { description = "Dropdown Terminal" })
hl.bind(modifier .. " + T", hl.dsp.exec_cmd("thunar"), { description = "Thunar" })
hl.bind(modifier .. " + ALT + M", hl.dsp.exec_cmd("pavucontrol"), { description = "Audio Control" })

-- ================================================================
-- WINDOW MANAGEMENT
-- ================================================================
hl.bind(modifier .. " + Q", hl.dsp.window.close(), { description = "Kill Active Window" })
hl.bind(modifier .. " + P", hl.dsp.window.pseudo({ action = "toggle" }), { description = "Pseudo Tile" })
hl.bind(modifier .. " + SHIFT + I", hl.dsp.layout("togglesplit"), { description = "Toggle Split" })
hl.bind(modifier .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Maximize" })
hl.bind(modifier .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle Floating" })
hl.bind(modifier .. " + ALT + F", hl.dsp.exec_cmd("hyprland-float-all"), { description = "Float All Windows" })

-- ================================================================
-- LAYOUTS
-- ================================================================
hl.bind(modifier .. " + ALT + L", hl.dsp.exec_cmd("hyprland-change-layout toggle"), { description = "Toggle Layouts" })
hl.bind(modifier .. " + ALT + 1", hl.dsp.exec_cmd("hyprland-change-layout dwindle"), { description = "Layout Dwindle" })
hl.bind(modifier .. " + ALT + 2", hl.dsp.exec_cmd("hyprland-change-layout master"), { description = "Layout Master" })
hl.bind(modifier .. " + ALT + 3", hl.dsp.exec_cmd("hyprland-change-layout scrolling"), { description = "Layout Scrolling" })
hl.bind(modifier .. " + ALT + 4", hl.dsp.exec_cmd("hyprland-change-layout monocle"), { description = "Layout Monocle" })
hl.bind(modifier .. " + SHIFT + C", hl.dsp.exit(), { description = "Exit/Logout of Hyprland" })

-- ================================================================
-- WINDOW MOVEMENT (ARROW KEYS)
-- ================================================================
hl.bind(modifier .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }), { description = "Move Left" })
hl.bind(modifier .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), { description = "Move Right" })
hl.bind(modifier .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }), { description = "Move Up" })
hl.bind(modifier .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }), { description = "Move Down" })

-- ================================================================
-- WINDOW MOVEMENT (VI STYLE)
-- ================================================================
hl.bind(modifier .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }), { description = "Move Left (VI)" })
hl.bind(modifier .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }), { description = "Move Right (VI)" })
hl.bind(modifier .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }), { description = "Move Up (VI)" })
hl.bind(modifier .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }), { description = "Move Down (VI)" })

-- ================================================================
-- WINDOW SWAPPING (ARROW KEYS)
-- ================================================================
hl.bind(modifier .. " + ALT + left", hl.dsp.window.swap({ direction = "left" }), { description = "Swap Left" })
hl.bind(modifier .. " + ALT + right", hl.dsp.window.swap({ direction = "right" }), { description = "Swap Right" })
hl.bind(modifier .. " + ALT + up", hl.dsp.window.swap({ direction = "up" }), { description = "Swap Up" })
hl.bind(modifier .. " + ALT + down", hl.dsp.window.swap({ direction = "down" }), { description = "Swap Down" })

-- ================================================================
-- WINDOW SWAPPING (VI KEYCODES)
-- ================================================================
hl.bind(modifier .. " + ALT + code:43", hl.dsp.window.swap({ direction = "left" }), { description = "Swap Left (VI)" })
hl.bind(modifier .. " + ALT + code:46", hl.dsp.window.swap({ direction = "right" }), { description = "Swap Right (VI)" })
hl.bind(modifier .. " + ALT + code:45", hl.dsp.window.swap({ direction = "up" }), { description = "Swap Up (VI)" })
hl.bind(modifier .. " + ALT + code:44", hl.dsp.window.swap({ direction = "down" }), { description = "Swap Down (VI)" })

-- ================================================================
-- FOCUS MOVEMENT (ARROW KEYS)
-- ================================================================
hl.bind(modifier .. " + left", hl.dsp.focus({ direction = "left" }), { description = "Focus Left" })
hl.bind(modifier .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focus Right" })
hl.bind(modifier .. " + up", hl.dsp.focus({ direction = "up" }), { description = "Focus Up" })
hl.bind(modifier .. " + down", hl.dsp.focus({ direction = "down" }), { description = "Focus Down" })

-- ================================================================
-- FOCUS MOVEMENT (VI STYLE)
-- ================================================================
hl.bind(modifier .. " + h", hl.dsp.focus({ direction = "left" }), { description = "Focus Left (VI)" })
hl.bind(modifier .. " + l", hl.dsp.focus({ direction = "right" }), { description = "Focus Right (VI)" })
hl.bind(modifier .. " + k", hl.dsp.focus({ direction = "up" }), { description = "Focus Up (VI)" })
hl.bind(modifier .. " + j", hl.dsp.focus({ direction = "down" }), { description = "Focus Down (VI)" })

-- ================================================================
-- WORKSPACE SWITCHING (1-10)
-- ================================================================
for i = 1, 9 do
  hl.bind(modifier .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "Workspace " .. i })
end
hl.bind(modifier .. " + 0", hl.dsp.focus({ workspace = 10 }), { description = "Workspace 10" })

-- ================================================================
-- MOVE WINDOW TO WORKSPACE (1-10)
-- ================================================================
hl.bind(modifier .. " + SHIFT + SPACE", hl.dsp.window.move({ workspace = "special" }), { description = "Move to Special" })
hl.bind(modifier .. " + SPACE", hl.dsp.workspace.toggle_special(), { description = "Toggle Special" })
for i = 1, 9 do
  hl.bind(modifier .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }), { description = "Move to Workspace " .. i })
end
hl.bind(modifier .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }), { description = "Move to Workspace 10" })

-- ================================================================
-- WORKSPACE NAVIGATION
-- ================================================================
hl.bind(modifier .. " + CONTROL + right", hl.dsp.focus({ workspace = "e+1" }), { description = "Next Workspace" })
hl.bind(modifier .. " + CONTROL + left", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous Workspace" })
hl.bind(modifier .. " + mouse:down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next Workspace Mouse" })
hl.bind(modifier .. " + mouse:up", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous Workspace Mouse" })

-- ================================================================
-- WINDOW CYCLING
-- ================================================================
hl.bind("ALT + Tab", function()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end, { description = "Cycle Next Window / Bring Active To Top" })

-- ================================================================
-- MEDIA & HARDWARE CONTROLS
-- Volume/brightness/mute routed through Noctalia IPC so the OSD
-- stays in sync with the shell. Playback keys use playerctl directly
-- since Noctalia doesn't own those.
-- ================================================================
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("noctalia msg volume-up"), { locked = true, repeating = true, description = "Volume Up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("noctalia msg volume-down"), { locked = true, repeating = true, description = "Volume Down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("noctalia msg volume-mute"), { locked = true, description = "Mute Toggle" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("noctalia msg brightness-up"), { locked = true, repeating = true, description = "Brightness Up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("noctalia msg brightness-down"), { locked = true, repeating = true, description = "Brightness Down" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play Pause" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play Pause" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, description = "Next Track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, description = "Previous Track" })
    '';
  };

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
}

