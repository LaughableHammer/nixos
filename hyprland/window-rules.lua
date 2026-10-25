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

hl.window_rule({
  match = { class = "com.gabm.satty" },
  float = true,
  center = true,
  pin = true,
})

-- kitty restores its previous window state from its own cache. Hyprland reports
-- tiled windows as "maximized", so that cache records "maximized" and every new
-- kitty instance asks to open filling the screen. Ignore those requests; this
-- only drops client-side maximize requests, so SUPER+F still works.
hl.window_rule({
  name = "kitty-no-maximize",
  match = { class = "kitty" },
  suppress_event = "maximize",
})
