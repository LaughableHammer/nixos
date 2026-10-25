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
pi -local          # no network in the sandbox (combine with any of the above)
pi -insecure       # no sandbox at all, tools run on the host
pi -yes            # accept a broad-mount warning non-interactively
```

`-local` removes network access from the sandbox only; Pi still reaches the model
provider. Copy files in from another terminal at the printed scratch path
(available inside the container as `/tmp`).

Package and auth subcommands (`pi update`, `pi install`, `pi config`, `pi auth`,
`pi --help`, …) always run on the host, because they need the host's network,
store and credentials.

Session resumption is unchanged: the working directory is mounted at its real
path, so `pi -r` still finds sessions under the same key. Only sandbox-local
state (`/tmp`, the scratch directory) is gone between runs, which the model is
told about in its guidelines.

## What the sandbox can and cannot do

| Resource | Access |
|---|---|
| `/nix/store`, `/nix/var/nix/profiles`, `/run/current-system/sw/bin` | read-only; all OS-installed tools keep working |
| working directory | per flag (`-cwd`, `-cwdro`, `-copy`) |
| `/tmp` (= the host scratch directory, mode 700, deleted on exit) | read-write |
| `$HOME` (container `/tmp/home`) | ephemeral, not the host home |
| network | enabled unless `-local` |
| Docker socket, nix daemon socket, host `/proc`, host `/dev`, other users' homes | not mounted |

`apk` is available in the container, and `uv` for Python packages. Nix builds do
not work inside the sandbox; the model is told to ask you to run `nix build` on
the host.

## Mount safety

`-cwd`, `-cwdro` and `-copy` are checked before anything starts:

- **Refused:** `/`, `/home`, `/root`, `/nix*`, `/etc`, `/usr`, `/var`, `/run`,
  `/tmp`, `/boot`, `/dev`, `/proc`, `/sys`, and any path that contains `$HOME`.
- **Warned and confirmed:** a "broad" mount — `$HOME` itself, or any directory
  that contains one of the masked paths below. In a script pass `-yes`; without a
  terminal the run is refused.
- **Masked inside an allowed mount:** the paths in `my.piSandbox.maskPaths`
  (default: `~/.pi`, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`,
  `~/.config`, `~/.local/bin`, `~/.local/share/keyrings`, `~/.npmrc`,
  `~/.netrc`, `~/.git-credentials`, `~/.gitconfig`, `~/.mozilla`, shell rc files).
  Directories are replaced with an empty 1 MiB tmpfs, files with an empty
  read-only file, so `pi -cwd` from `$HOME` cannot read credentials or drop
  autostart/shell-rc payloads.
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
pi-sandbox-shell -cwdro -local # interactive shell with the same mounts
```

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
- `-cwd` writes are real host writes; there is no overlay.
