# Pi sandbox

Pi's built-in tools (`read`, `write`, `edit`, `ls`, `find`, `grep`, `bash`) run
inside a Docker container. Pi itself — the harness that holds
`~/.pi/agent/auth.json`, talks to OpenRouter, writes session files and runs
extensions — stays on the host, so no tool call can read or exfiltrate provider
credentials.

```
pi (host, trusted)                     container (untrusted)
 ├── auth.json, sessions, extensions    /nix/store        read-only
 ├── provider HTTPS                     $PWD              read-only | read-write | absent
 └── sandbox extension ──NDJSON──►      /tmp              scratch, deleted on exit
     sandboxd (node) ── bash -c, file ops
```

## Usage

```bash
pi                 # sandboxed, working directory not mounted
pi -cwd            # working directory mounted read-write at the same path
pi -cwdro          # working directory mounted read-only
pi -copy           # no host mount: a private copy of the working directory in /tmp/work
pi -extraro DIR    # mount an extra directory read-only at its real path (repeatable)
pi -extrarw DIR    # mount an extra directory read-write at its real path (repeatable)
pi -local          # no network in the sandbox (combine with any of the above)
pi -insecure       # no sandbox at all, tools run on the host
pi -yes            # accept a broad-mount warning non-interactively
```

Extra mounts are independent of the working-directory mode, so
`pi -cwd -extraro ../shared -extrarw ~/scratch` mounts the project read-write,
`../shared` read-only and `~/scratch` read-write, while `pi -extraro ~/data`
mounts only `~/data` and leaves the working directory at `/tmp`. Each extra is
mounted at the same absolute path it has on the host, so the model must use that
absolute path (`~` inside the container is the ephemeral `/tmp/home`). An extra
that is already covered by another mount (the same directory, or one inside it)
is skipped with a log line. `-copy` cannot be combined with extras, because copy
mode mounts nothing from the host.

`-local` removes network access from the sandbox only; Pi still reaches the model
provider. Copy files in from another terminal at the printed scratch path
(available inside the container as `/tmp`).

Package and auth subcommands (`pi update`, `pi install`, `pi config`, `pi auth`,
`pi --help`, …) always run on the host, because they need the host's network,
store and credentials.

## Resuming a session

The working directory is mounted at its real path, so `pi -r` still finds
sessions under the same key. Only sandbox-local state (`/tmp`, the scratch
directory) is gone between runs, which the model is told about in its
guidelines.

Every sandboxed run appends a `pi-sandbox.config` custom entry to its session
(the entry is not part of the model's context). When `pi -r`, `pi -c`,
`--session` or `--fork` is used **without** explicit sandbox flags, Pi's picker
runs first; once a session is loaded the sandbox extension offers:

- **Reuse previous sandbox** — the mount mode, network mode and extra mounts of
  the most recent run of that session. The working directory is always the
  current launch directory, not a directory from the old run.
- **Use default sandbox** — `my.piSandbox.defaultMode`, network on, no extras.
  This is also the only option (besides exiting) for sessions recorded before
  this feature.
- **Exit Pi** — print the restart hint and quit. To pick different mounts, exit
  and rerun `pi -cwd -r`, `pi -cwdro -r`, `pi -copy -r`, or add
  `-extraro DIR`/`-extrarw DIR`; explicit flags always win and skip the prompt.

Reusing a broad mount repeats the normal broad-mount confirmation. Declining it
falls back to the default sandbox. If a recorded extra directory no longer
exists, the reuse fails with a notice and the default sandbox is used. Sessions
started with `pi -insecure` are never recorded, so `pi -r` always applies a
sandbox; use `pi -insecure -r` to resume one unsandboxed.

Sandbox mounts cannot change while Pi is running. Selecting a different session
with `/resume` mid-run only warns when its recorded sandbox differs from the
active one; exit and run `pi -r` again to apply that session's sandbox.

The footer status describes the current run's container:

- `cwd rw` / `cwd ro` — the working directory is mounted read-write or read-only
- `cwd copy` — nothing is mounted; a private copy lives at `/tmp/work`
- `/tmp only` — nothing is mounted; this is `defaultMode = none`, not an
  unsandboxed run

## What the sandbox can and cannot do

| Resource | Access |
|---|---|
| `/nix/store`, `/nix/var/nix/profiles`, `/run/current-system/sw/bin` | read-only; all OS-installed tools keep working |
| working directory | per flag (`-cwd`, `-cwdro`, `-copy`) |
| extra directories | per flag (`-extraro` read-only, `-extrarw` read-write), masked like the working directory |
| `/tmp` (= the host scratch directory, mode 700, deleted on exit) | read-write |
| `$HOME` (container `/tmp/home`) | ephemeral, not the host home |
| network | enabled unless `-local` |
| Docker socket, nix daemon socket, host `/proc`, host `/dev`, other users' homes | not mounted |

`apk` is available in the container, and `uv` for Python packages. Nix builds do
not work inside the sandbox; the model is told to ask you to run `nix build` on
the host.

## Mount safety

`-cwd`, `-cwdro`, `-copy`, `-extraro` and `-extrarw` are checked before
anything starts, and every extra is checked exactly like the working directory:

- **Refused:** `/`, `/home`, `/root`, `/nix*`, `/etc`, `/usr`, `/var`, `/run`,
  `/tmp`, `/boot`, `/dev`, `/proc`, `/sys`, and any path that contains `$HOME`.
- **Warned and confirmed:** a "broad" mount — `$HOME` itself, or any directory
  that contains one of the masked paths below. In a script pass `-yes`; without a
  terminal the run is refused.
- **Masked inside any allowed mount:** the paths in `my.piSandbox.maskPaths`
  (default: `~/.pi`, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`,
  `~/.config`, `~/.local/bin`, `~/.local/share/keyrings`, `~/.npmrc`,
  `~/.netrc`, `~/.git-credentials`, `~/.gitconfig`, `~/.mozilla`, shell rc files).
  Directories are replaced with an empty 1 MiB tmpfs, files with an empty
  read-only file, so `pi -cwd` from `$HOME` cannot read credentials or drop
  autostart/shell-rc payloads. The same list applies to every extra mount, so
  `pi -extrarw ~` still hides `~/.ssh` and `~/.config`, and a mount nested
  inside another mount gets the masks too.
- **`-copy`** is the strongest option for untrusted trees: nothing from the host
  is mounted, masked paths are excluded from the copy, and results are copied out
  of the scratch directory.

Masking is a fixed list, not secret detection: a `secrets/` directory inside a
mounted project stays readable. Use `-copy`, or don't mount that directory.

## Requirements

- Rootless Docker (`virtualisation.docker.rootless.enable`). Sandbox runs pick
  the rootless socket via `DOCKER_HOST`; without it the container falls back to
  running as your uid and `apk` is unavailable (a warning is printed).
- `dockerTools.pullImage` pins the Alpine base. Update the digest and hash with:

  ```bash
  nix shell nixpkgs#nix-prefetch-docker -c nix-prefetch-docker \
    --image-name alpine --image-tag 3.24.2 --os linux --arch amd64 \
    --final-image-name pi-sandbox-alpine --final-image-tag 3.24.2
  ```

## Verification

```bash
pi-sandbox-doctor none         # isolation, masks, tools
pi-sandbox-doctor ro
pi-sandbox-doctor rw
PI_SANDBOX_DOCTOR_NET=0 pi-sandbox-doctor rw   # also checks that -local blocks egress
pi-sandbox-doctor rw -extraro ~/data -extrarw ~/scratch  # also probes extra mounts
pi-sandbox-shell -cwdro -local # interactive shell with the same mounts
pi-sandbox-shell -extraro ~/data -extrarw ~/scratch

# Policy-only check used by resume: no scratch, no container
pi-sandbox-preflight -cwd
pi-sandbox-preflight -copy -local
pi-sandbox-preflight -cwd -extraro ~/data
```

`pi-sandbox-doctor` accepts the same `-extraro`/`-extrarw` arguments as `pi`; it
reports each extra as readable (read-only) or writable (read-write), and checks
that masked paths inside the extras are still empty.

## Residual risk

- The container shares the host kernel; a kernel or runtime escape is out of
  scope for this boundary (Docker's seccomp profile, dropped privileges and the
  user namespace are the defence).
- Extensions, Pi packages and MCP servers run in the host Pi process and are not
  sandboxed. That includes the user-level extensions in `../extensions/` (see
  `../extensions/README.md`). Set `my.piSandbox.strictTools = true` to block tool
  calls outside the sandboxed built-ins, and keep `defaultProjectTrust = "never"`.
- With network enabled, anything the agent can read can leave the machine; use
  `-local` for sensitive work.
- `-local` only removes the container's network. Host-side extensions keep
  whatever network the Pi process has, so they must honour `PI_WEB=0`
  themselves; `web_search` (see `../extensions/README.md`) does, and exports it
  from the launcher.
- `-cwd`, `-extrarw` and `-extraro` write paths are real host writes; there is
  no overlay.
