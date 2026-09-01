local modifier = "SUPER"

hl.bind(modifier .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(modifier .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("mouse:276", hl.dsp.focus({ workspace = "e+1" }), { mouse = true })
hl.bind("mouse:275", hl.dsp.focus({ workspace = "e-1" }), { mouse = true })
