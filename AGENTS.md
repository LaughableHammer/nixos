# AGENTS.md

Personal NixOS flake configuration for host `hammernix`, user `laughablehammer`.

## Structure

- `flake.nix` — flake entry point; `mkHost` composes `configuration.nix`, `hosts/<name>/`, and home-manager (`home.nix` + `hosts/<name>/home.nix`). All modules receive `inputs`, `hostName`, and `userName` via specialArgs.
- `configuration.nix` — shared NixOS system config.
- `home.nix` — shared home-manager config.
- `hosts/hammernix/` — host-specific config (incl. `hardware-configuration.nix`, Hyprland monitor/workspace Lua).
- `modules/` — reusable NixOS (`modules/nixos`) and home-manager (`modules/home`) modules.
- `modules/home/ai/pi/` — Pi coding agent: launcher, settings/models, extensions, and the Docker-backed tool sandbox in `sandbox/`.
- `hyprland/` — Hyprland Lua config fragments, imported by `modules/home/hyprland`.
- `noctalia-base.toml` / `noctalia-gui-overrides.toml` — Noctalia theming.

## Build & apply

- `sudo nixos-rebuild switch --flake .` (or `./build.sh`, which stages everything first).
- Update inputs: `nix flake update` (or target a single input), then rebuild — but read **Pinned inputs** first; several inputs must not be updated blindly.
- Never edit `flake.lock` or `hardware-configuration.nix` by hand.

## Pinned inputs

Some inputs are pinned to specific revisions in `flake.nix`. Do not blindly `nix flake update` them:

- `nixpkgs` → `7fd4004d0511991fff3a0524856a9be09e28c5f0`. This is the revision Hyprland `8010b4e` was built against, so Hyprland stays prebuilt and mesa stays in lockstep. Bumping it out of step with the Hyprland input rebuilds mesa/libdrm against a different toolchain than the cached Hyprland, which makes aquamarine fail with `gbm failed to create a device` and Hyprland crash back to the login screen. Update `nixpkgs` and the Hyprland input together.
- `hyprland` → `8010b4e5c66f97aa82cd5b3332b4ec613779b9a7`, `noctalia` → `e37d7145b95a51b801db9bb20d1c600f35111e0b`. Pinned so `nix flake update` cannot move them unexpectedly; `hyprland` follows the pinned `nixpkgs`.
- `nixpkgs-llama` → `7a0f122f5090cf4c2ade2a13a0e229d4e19ba71f`. Only feeds `services.llama-cpp`'s ROCm build (`modules/nixos/ai/default.nix`). ROCm llama-cpp is not in any binary cache, so this pin exists to keep that build cached; expect a one-time source build whenever you bump it.
- `home-manager` and `nix-gaming` follow `nixpkgs` (`inputs.nixpkgs.follows = "nixpkgs"`), so they track the pinned `nixpkgs` automatically.
- The Pi sandbox Alpine base image is pinned by digest and hash in `modules/home/ai/pi/sandbox/default.nix`; update it with `nix-prefetch-docker` (see the comment there and `sandbox/README.md`).

## Pi sandbox

`modules/home/ai/pi/sandbox/` routes Pi's built-in tools into a Docker container while the harness (credentials, provider traffic, sessions, extensions) stays on the host:

- `default.nix` — all policy: the Alpine image pin, mount/refusal/masking rules (`pi-sandbox-lib.sh`), the container invocation (`pi-sandbox-exec`), the `pi` launcher, and the `pi-sandbox-shell`/`pi-sandbox-doctor` helpers. Options live under `my.piSandbox`.
- `sandboxd.mjs` — supervisor inside the container; serves file operations and `bash -c` over newline-delimited JSON.
- `extension.ts` — thin client in the host Pi process: tool-operation adapters, `grep`/`find` routed to sandboxed `rg`/`fd`, and the short sandbox guidelines appended to the system prompt.
- Flags: `-cwd` (mount rw), `-cwdro` (mount ro), `-copy` (no mount, private copy), `-local` (no sandbox network), `-insecure` (no sandbox), `-yes` (accept broad-mount warning).
- Keep policy in Nix, not in the extension: the container, not the client, decides what a path means.
- Requires rootless Docker (`virtualisation.docker.rootless`); `pi-sandbox-doctor <none|ro|rw|copy>` verifies isolation, masks and tooling.

## Pi extensions

- `modules/home/ai/pi/extensions/` is exposed recursively as `~/.pi/agent/extensions` and auto-discovered by Pi: adding `<name>.ts` there needs no Nix change. The files are store symlinks, so rebuild (`sudo nixos-rebuild switch --flake .`) before restart/`/reload`, and document the extension in `extensions/README.md`.
- Extensions run trusted in the host Pi process, outside the sandbox, with full filesystem and network access; the sandbox only covers Pi's built-in tools.
- `modules/home/ai/pi/sandbox/extension.ts` is the exception: the launcher force-loads it with `-e` and disables built-in tools with `-nbt`. A second sandbox-coupled extension needs a `writeText` binding, `my.piSandbox.extension` widened from a single path, and an extra `-e` argument in the launcher.

## Conventions

- Nix formatting: `nixfmt` style (2-space indent, attributes on one line where reasonable).
- No local package overrides; software comes from nixpkgs, flake inputs, or module options.
- Host-specific settings belong in `hosts/hammernix/`, shared settings in the top-level or `modules/` files.

## Testing changes

- `nix flake check` is not wired up; validate with `nixos-rebuild build --flake .` before switching, and prefer `nixos-rebuild test` for risky changes since a bad `switch` requires a rollback at boot.
- Pi sandbox changes: run `pi-sandbox-doctor none|ro|rw|copy` (and `PI_SANDBOX_DOCTOR_NET=0` for the `-local` network checks) after switching. Rootless Docker only exists after a switch, so the fallback path (uid-mapped container, no `apk`) is what runs before it.
