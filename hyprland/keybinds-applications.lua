local modifier = "SUPER"

hl.bind(modifier .. " + Return", hl.dsp.exec_cmd("kitty"), { description = "Terminal" })
hl.bind(modifier .. " + D", hl.dsp.exec_cmd("vesktop"), { description = "Vesktop" })
hl.bind(modifier .. " + S", hl.dsp.exec_cmd("spotify"), { description = "Spotify" })
hl.bind(modifier .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -rs"), { description = "Notification Reset" })
hl.bind(modifier .. " + W", hl.dsp.exec_cmd("firefox"), { description = "Web Browser" })
hl.bind(modifier .. " + ALT + C", hl.dsp.exec_cmd("hyprpicker -a"), { description = "Color Picker" })
hl.bind(modifier .. " + T", hl.dsp.exec_cmd("thunar"), { description = "Thunar" })