# AGENTS.md

Personal NixOS flake configuration for host `hammernix`, user `laughablehammer`.

## Structure

- `flake.nix` — flake entry point; `mkHost` composes `configuration.nix`, `hosts/<name>/`, and home-manager (`home.nix` + `hosts/<name>/home.nix`). All modules receive `inputs`, `hostName`, and `userName` via specialArgs.
- `configuration.nix` — shared NixOS system config.
- `home.nix` — shared home-manager config.
- `hosts/hammernix/` — host-specific config (incl. `hardware-configuration.nix`, Hyprland monitor/workspace Lua).
- `modules/` — reusable NixOS (`modules/nixos`) and home-manager (`modules/home`) modules.
- `hyprland/` — Hyprland Lua config fragments, imported by `modules/home/hyprland`.
- `noctalia-base.toml` / `noctalia-gui-overrides.toml` — Noctalia theming.

## Build & apply

- `sudo nixos-rebuild switch --flake .` (or `./build.sh`, which stages everything first).
- Update inputs: `nix flake update` (or target a single input), then rebuild.
- Never edit `flake.lock` or `hardware-configuration.nix` by hand.

## Conventions

- Nix formatting: `nixfmt` style (2-space indent, attributes on one line where reasonable).
- No local package overrides; software comes from nixpkgs, flake inputs, or module options.
- Host-specific settings belong in `hosts/hammernix/`, shared settings in the top-level or `modules/` files.

## Testing changes

- `nix flake check` is not wired up; validate with `nixos-rebuild build --flake .` before switching, and prefer `nixos-rebuild test` for risky changes since a bad `switch` requires a rollback at boot.
