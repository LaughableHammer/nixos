# Pi extensions

## Adding an extension

1. Add `<name>.ts` to this directory, default-exporting a function of the form
   `(pi: ExtensionAPI) => void` (see `plan.ts` for the API in use).
2. No Nix change is needed: `modules/home/ai/pi/default.nix` exposes this
   directory recursively as `~/.pi/agent/extensions`, which Pi auto-discovers.
3. Rebuild, then restart Pi or run `/reload`:
   `sudo nixos-rebuild switch --flake .` (or `./build.sh`).
4. Document the extension below.

The files exposed here are symlinks into the Nix store, so editing an extension
in this repository has no effect until the rebuild — `/reload` alone will not
pick up the change.

Extensions run in the host Pi process, outside the Docker sandbox, so they have
full filesystem and network access and may spawn host commands (as
`notifications.ts` does with Noctalia). Only the sandbox extension in
`../sandbox/extension.ts` mediates sandboxed tool calls; see
`../sandbox/README.md`.

## `/plan`

`plan.ts` adds an approval-gated planning mode to Pi. It is based on Pi's
extension APIs and the upstream `examples/extensions/plan-mode` example, but is
intentionally smaller and stricter:

- only `read`, `grep`, `find`, and `ls` are enabled while planning;
- the model must propose a numbered solution before implementation;
- the model is told not to ask its own approval question;
- Pi presents explicit **Implement**, **Revise**, **Keep planning**, and
  **Cancel** choices after the proposal;
- the tool set active before planning is restored only after approval or
  cancellation;
- plan state survives session resume.

Home Manager exposes this directory as `~/.pi/agent/extensions`, so after
applying the configuration, restart Pi or run `/reload`.

### Usage

```text
/plan add health checks to the service
/plan revise include an integration test
/plan implement
/plan cancel
```

Running `/plan` without arguments toggles plan mode: it enables read-only plan
mode when inactive, and disables it (restoring the previous tools) when active.
In the interactive TUI, implementation/revision choices appear automatically
after each proposal. The explicit subcommands are useful when a UI selector is
unavailable.

This is a slash command, not an LLM-callable custom tool: that is preferable
for an approval boundary because the user, rather than the model, controls when
planning starts and when implementation is authorized.

## OpenRouter balance

`openrouter-balance.ts` adds an `or: $X.XX` item to the footer while an
OpenRouter model is selected. It reads the active key from Pi's model registry
and queries OpenRouter directly:

- a key with a fixed `limit` shows that limit minus its usage;
- an unlimited key shows the account's remaining credits
  (`total_credits - total_usage`).

The value is cached for a minute and refreshed on session start, model change,
and after each settled agent run. `/or-balance` forces a fresh lookup and
reports whether the number is a per-key limit or account credits.

## Web search

`brave-search.ts` adds a `web_search` tool backed by the Brave Search CLI
(`bx`, from `pkgs.brave-search-cli`). `bx context` returns pre-extracted,
token-budgeted page text in one call, so the extension does no HTTP or HTML
handling: it only builds the arguments, truncates the JSON to Pi's limits
(full output is written to a temp file when truncated), and renders the result.
The optional `maxTokens` parameter (512–8192, default 2048) maps to
`--max-tokens`.

Setup is manual because the key must not live in the Nix store:

```bash
bx config set-key          # interactive; writes ~/.config/brave-search/config.json
bx config path             # where the key is stored
```

`BRAVE_SEARCH_API_KEY` is also honoured. `~/.config` is in
`my.piSandbox.maskPaths`, so the container cannot read the key, and it must not
be mounted into the sandbox. The free Brave plan includes about 1,000 queries
per month; the CLI maps auth and rate-limit failures to distinct exit codes,
which the tool reports as hints.

`web_search` runs `bx` on the host, not in the container, so the sandbox's
network policy does not apply to it. Two things disable it instead:

- `pi -local` exports `PI_WEB=0` and the tool is not registered; the footer
  shows `web: off (network disabled by -local)`. `--network none` only covers
  the container, and Pi itself still needs the model provider, so host-side
  tools have to be told about `-local` explicitly.
- `my.piSandbox.strictTools = true` blocks host-side tools, and
  `PI_SANDBOX_STRICT=1` likewise skips registration.

`PI_WEB=0 pi` disables it independently of the sandbox, including under
`-insecure`.

## Desktop notifications

`notifications.ts` raises a desktop notification through Noctalia:

- when an agent run settles and Pi is waiting for the next prompt; the body
  includes the working directory and the start of Pi's last reply;
- when a blocking extension UI prompt opens (for example the `/plan` approval
  selector), marked as critical so it does not time out unnoticed.

Notifications are best-effort. On Hyprland, notifications are suppressed
whenever the kitty window containing Pi is the focused window, so dialogs you
are already looking at (for example `/or-model`) do not produce a desktop
notification. Toggle them with:

```text
/notify on
/notify off
/notify status
```

Set `PI_NOTIFICATIONS=0` before launching Pi to start with notifications off.

Kitty is configured separately (in `modules/home/software/notifications.nix`)
to use its built-in shell integration and to notify when an unfocused command
lasting at least five seconds finishes. Kitty only tracks commands entered at
the shell prompt; commands spawned by Pi's bash tool are captured by Pi rather
than reported as shell-integration jobs, so they do not produce completion
notifications.

