# Pi extensions

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

