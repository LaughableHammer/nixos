-- DP-2: main landscape panel, 2560x1440 @180Hz, at 0x0.
hl.monitor({ output = "DP-2", mode = "2560x1440@180", position = "0x0", scale = 1.0, vrr = 2 })

-- HDMI-A-1: portrait panel to the right, vertically centered with DP-2.
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@120", position = "2560x-240", scale = 1.0, transform = 1, vrr = 0 })
