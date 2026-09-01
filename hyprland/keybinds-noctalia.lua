local modifier = "SUPER"

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
hl.bind(modifier .. " + SHIFT + S", hl.dsp.exec_cmd("noctalia msg screenshot-region"), { description = "Noctalia Screenshot Region" })
hl.bind(modifier .. " + SHIFT + R", hl.dsp.exec_cmd("restart.noctalia"), { description = "Restart Noctalia Shell" })
hl.bind(modifier .. " + Space", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "Noctalia Launcher (Space)" })

hl.bind(modifier .. " + CTRL + D", hl.dsp.exec_cmd("dock"), { description = "Toggle Dock" })
hl.bind(modifier .. " + Tab", hl.dsp.exec_cmd("qs ipc -c overview call overview toggle"), { description = "QS Overview" })
