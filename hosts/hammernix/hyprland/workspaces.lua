-- Primary monitor
for i = 1, 5 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "DP-2", persistent = true })
end

-- Secondary monitor
for i = 6, 10 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "HDMI-A-1", persistent = true })
end
