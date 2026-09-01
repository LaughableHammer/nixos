local modifier = "SUPER"

hl.bind(modifier .. " + CTRL + S", hl.dsp.exec_cmd("hyprshot -m output -o $HOME/Pictures/ScreenShots"), { description = "Screenshot Output" })
hl.bind(modifier .. " + ALT + S", hl.dsp.exec_cmd("hyprshot -m region -o $HOME/Pictures/ScreenShots"), { description = "Screenshot Region" })
hl.bind("End", hl.dsp.exec_cmd("hyprshot -m output -o $HOME/Pictures/ScreenShots"), { description = "Screenshot Output (End)" })
