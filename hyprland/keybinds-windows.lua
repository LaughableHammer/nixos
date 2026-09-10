local modifier = "SUPER"

-- Window state and layouts
hl.bind(modifier .. " + Q", hl.dsp.window.close(), { description = "Kill Active Window" })
hl.bind(modifier .. " + SHIFT + Q", hl.dsp.window.kill(), { description = "Force Kill Active Window" })
hl.bind(modifier .. " + P", hl.dsp.window.pseudo({ action = "toggle" }), { description = "Pseudo Tile" })
hl.bind(modifier .. " + SHIFT + I", hl.dsp.layout("togglesplit"), { description = "Toggle Split" })
hl.bind(modifier .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Maximize" })
hl.bind(modifier .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle Floating" })
hl.bind(modifier .. " + ALT + F", hl.dsp.exec_cmd("hyprland-float-all"), { description = "Float All Windows" })
hl.bind(modifier .. " + ALT + L", hl.dsp.exec_cmd("hyprland-change-layout toggle"), { description = "Toggle Layouts" })
hl.bind(modifier .. " + ALT + 1", hl.dsp.exec_cmd("hyprland-change-layout dwindle"), { description = "Layout Dwindle" })
hl.bind(modifier .. " + ALT + 2", hl.dsp.exec_cmd("hyprland-change-layout master"), { description = "Layout Master" })
hl.bind(modifier .. " + ALT + 3", hl.dsp.exec_cmd("hyprland-change-layout scrolling"), { description = "Layout Scrolling" })
hl.bind(modifier .. " + ALT + 4", hl.dsp.exec_cmd("hyprland-change-layout monocle"), { description = "Layout Monocle" })
hl.bind(modifier .. " + SHIFT + C", hl.dsp.exit(), { description = "Exit/Logout of Hyprland" })

-- Move windows
hl.bind(modifier .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }), { description = "Move Left" })
hl.bind(modifier .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), { description = "Move Right" })
hl.bind(modifier .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }), { description = "Move Up" })
hl.bind(modifier .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }), { description = "Move Down" })
hl.bind(modifier .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }), { description = "Move Left (VI)" })
hl.bind(modifier .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }), { description = "Move Right (VI)" })
hl.bind(modifier .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }), { description = "Move Up (VI)" })
hl.bind(modifier .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }), { description = "Move Down (VI)" })

-- Swap windows
hl.bind(modifier .. " + ALT + left", hl.dsp.window.swap({ direction = "left" }), { description = "Swap Left" })
hl.bind(modifier .. " + ALT + right", hl.dsp.window.swap({ direction = "right" }), { description = "Swap Right" })
hl.bind(modifier .. " + ALT + up", hl.dsp.window.swap({ direction = "up" }), { description = "Swap Up" })
hl.bind(modifier .. " + ALT + down", hl.dsp.window.swap({ direction = "down" }), { description = "Swap Down" })
hl.bind(modifier .. " + ALT + code:43", hl.dsp.window.swap({ direction = "left" }), { description = "Swap Left (VI)" })
hl.bind(modifier .. " + ALT + code:46", hl.dsp.window.swap({ direction = "right" }), { description = "Swap Right (VI)" })
hl.bind(modifier .. " + ALT + code:45", hl.dsp.window.swap({ direction = "up" }), { description = "Swap Up (VI)" })
hl.bind(modifier .. " + ALT + code:44", hl.dsp.window.swap({ direction = "down" }), { description = "Swap Down (VI)" })

-- Focus windows
hl.bind(modifier .. " + left", hl.dsp.focus({ direction = "left" }), { description = "Focus Left" })
hl.bind(modifier .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focus Right" })
hl.bind(modifier .. " + up", hl.dsp.focus({ direction = "up" }), { description = "Focus Up" })
hl.bind(modifier .. " + down", hl.dsp.focus({ direction = "down" }), { description = "Focus Down" })
hl.bind(modifier .. " + h", hl.dsp.focus({ direction = "left" }), { description = "Focus Left (VI)" })
hl.bind(modifier .. " + l", hl.dsp.focus({ direction = "right" }), { description = "Focus Right (VI)" })
hl.bind(modifier .. " + k", hl.dsp.focus({ direction = "up" }), { description = "Focus Up (VI)" })
hl.bind(modifier .. " + j", hl.dsp.focus({ direction = "down" }), { description = "Focus Down (VI)" })

hl.bind("ALT + Tab", function()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end, { description = "Cycle Next Window / Bring Active To Top" })
