local modifier = "SUPER"

-- Switch workspace
for i = 1, 9 do
  hl.bind(modifier .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "Workspace " .. i })
end
hl.bind(modifier .. " + 0", hl.dsp.focus({ workspace = 10 }), { description = "Workspace 10" })

-- Move the active window to a workspace
for i = 1, 9 do
  hl.bind(modifier .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }), { description = "Move to Workspace " .. i })
end
hl.bind(modifier .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }), { description = "Move to Workspace 10" })

-- Navigate workspaces
hl.bind(modifier .. " + CONTROL + right", hl.dsp.focus({ workspace = "e+1" }), { description = "Next Workspace" })
hl.bind(modifier .. " + CONTROL + left", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous Workspace" })
hl.bind(modifier .. " + mouse:down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next Workspace Mouse" })
hl.bind(modifier .. " + mouse:up", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous Workspace Mouse" })
