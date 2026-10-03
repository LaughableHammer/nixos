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
- Update inputs: `nix flake update` (or target a single input), then rebuild — but read **Pinned inputs** first; several inputs must not be updated blindly.
- Never edit `flake.lock` or `hardware-configuration.nix` by hand.

## Pinned inputs

Some inputs are pinned to specific revisions in `flake.nix`. Do not blindly `nix flake update` them:

- `nixpkgs` → `e554fab72f81915600f3f449b786fd9af40439a5`. This is the revision `hyprland.cachix.org` builds Hyprland against. Bumping it out of step with the Hyprland input rebuilds mesa/libdrm against a different toolchain than the cached Hyprland, which makes aquamarine fail with `gbm failed to create a device` and Hyprland crash back to the login screen. Update `nixpkgs` and the Hyprland input together (or only after Hyprland's flake advances its own pin).
- `nixpkgs-llama` → `7a0f122f5090cf4c2ade2a13a0e229d4e19ba71f`. Only feeds `services.llama-cpp`'s ROCm build (`modules/nixos/ai/default.nix`). ROCm llama-cpp is not in any binary cache, so this pin exists to keep that build cached; expect a one-time source build whenever you bump it.
- `home-manager` and `nix-gaming` follow `nixpkgs` (`inputs.nixpkgs.follows = "nixpkgs"`), so they track the pinned `nixpkgs` automatically.

## Conventions

- Nix formatting: `nixfmt` style (2-space indent, attributes on one line where reasonable).
- No local package overrides; software comes from nixpkgs, flake inputs, or module options.
- Host-specific settings belong in `hosts/hammernix/`, shared settings in the top-level or `modules/` files.

## Testing changes

- `nix flake check` is not wired up; validate with `nixos-rebuild build --flake .` before switching, and prefer `nixos-rebuild test` for risky changes since a bad `switch` requires a rollback at boot.
