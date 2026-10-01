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

## Cwd confinement

The Home Manager module installs a launcher in place of the package's direct
`pi` command:

```text
pi -cwd               # start a new confined session
pi -c                  # continue the normal, unconfined session
pi --continue          # same as pi -c
pi -cwd -c             # continue the cwd-local confined session
pi -cwd --continue     # same as pi -cwd -c
```

The launcher reserves the exact `-cwd` token for confinement and strips it
before starting Pi. Upstream Pi's `-c` and `--continue` flags keep their normal
meaning. Other arguments pass through unchanged. Calling the `pi-coding-agent`
binary directly by its Nix store path bypasses this launcher.

Confined state lives in `.pi-confined/` beneath the physical cwd:

- `home/` is the sandbox `HOME`;
- `agent/` contains cwd-local settings and the confinement extension;
- `sessions/` contains sessions used by `--continue`.

Bubblewrap provides the security boundary. The cwd is writable, while only the
Pi/tool Nix-store closure, a CA bundle, resolver files, `/dev`, and `/proc` are
exposed as runtime resources; `/tmp` is memory-backed. The network namespace is
shared so model providers remain reachable. Consequently, confinement protects
host files but does **not** prevent cwd data from being sent over the network.
Symlinks whose targets are outside the cwd do not resolve.

`~/.pi` and other host credential stores are not mounted. Supply provider
credentials through environment variables (for example `ANTHROPIC_API_KEY` or
`OPENAI_API_KEY`). Environment variables are inherited intentionally, including
custom provider endpoints and proxy settings. Avoid putting secrets unrelated
to Pi in the launch environment when using untrusted project code.

A quick check from Pi's bash tool should fail:

```sh
cat /etc/passwd
```

Reading and writing files in the cwd should still work. The companion
`cwd-confined.ts` extension shows a persistent status marker and rejects
explicit file-tool path escapes as defense in depth; it is not the security
boundary.
