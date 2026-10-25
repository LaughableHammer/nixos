{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.piSandbox;

  agentSlice = import ../agent-slice.nix { inherit pkgs; };

  # Pinned upstream image. Digest and hash come from `nix-prefetch-docker`:
  #   nix shell nixpkgs#nix-prefetch-docker -c nix-prefetch-docker \
  #     --image-name alpine --image-tag 3.24.2 --os linux --arch amd64 \
  #     --final-image-name pi-sandbox-alpine --final-image-tag 3.24.2
  alpineImage = pkgs.dockerTools.pullImage {
    imageName = "alpine";
    imageDigest = "sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6";
    hash = "sha256-Gbqy5TsZMM9TcL/StN2JvAKDiBNV8iMRRcu11N7Pc7w=";
    os = "linux";
    finalImageName = cfg.imageName;
    finalImageTag = cfg.imageTag;
  };

  sandboxd = pkgs.writeText "pi-sandboxd.mjs" (builtins.readFile ./sandboxd.mjs);
  extension = pkgs.writeText "pi-sandbox-extension.ts" (builtins.readFile ./extension.ts);

  docker = "${pkgs.docker}/bin/docker";
  node = "${pkgs.nodejs}/bin/node";
  bash = "${pkgs.bashInteractive}/bin/bash";
  tar = "${pkgs.gnutar}/bin/tar";
  cacertBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  sandboxTools = with pkgs; [
    bashInteractive
    coreutils
    gnused
    gnugrep
    findutils
    ripgrep
    fd
    git
    curl
    wget
    jq
    gnutar
    gzip
    xz
    zstd
    unzip
    diffutils
    patch
    less
    which
    procps
    file
    openssh
  ];

  sandboxBinPath = lib.makeBinPath sandboxTools;

  # Paths under $HOME that are masked out of any mounted directory. They hold
  # credentials, session data, or host-persistence vectors (shell rc files,
  # autostart entries, user units) that a read-write mount would otherwise expose.
  maskPaths = [
    ".pi"
    ".ssh"
    ".gnupg"
    ".aws"
    ".kube"
    ".docker"
    ".config"
    ".local/bin"
    ".local/share/keyrings"
    ".local/share/systemd"
    ".npmrc"
    ".netrc"
    ".git-credentials"
    ".gitconfig"
    ".mozilla"
    ".bashrc"
    ".bash_profile"
    ".bash_login"
    ".profile"
    ".zshrc"
    ".zshenv"
  ];

  maskPathsBash = lib.concatMapStringsSep "\n" (entry: "  ${lib.escapeShellArg entry}") maskPaths;

  # Shared shell library: refusal rules, masking, scratch lifecycle and the
  # sandbox environment. Sourced by the launcher and the helper commands so the
  # policy exists in exactly one place.
  sandboxLib = pkgs.writeText "pi-sandbox-lib.sh" ''
    # shellcheck shell=bash
    PI_SANDBOX_MASK_PATHS=(
    ${maskPathsBash}
    )

    # Static policy paths; a caller may override them before sourcing.
    PI_SANDBOX_DOCKER="''${PI_SANDBOX_DOCKER:-${docker}}"
    PI_SANDBOX_IMAGE="''${PI_SANDBOX_IMAGE:-${cfg.imageName}:${cfg.imageTag}}"
    PI_SANDBOX_IMAGE_TAR="''${PI_SANDBOX_IMAGE_TAR:-${alpineImage}}"
    PI_SANDBOX_TAR="''${PI_SANDBOX_TAR:-${tar}}"
    PI_SANDBOX_NODE="''${PI_SANDBOX_NODE:-${node}}"
    PI_SANDBOX_BASH="''${PI_SANDBOX_BASH:-${bash}}"
    PI_SANDBOX_SANDBOXD="''${PI_SANDBOX_SANDBOXD:-${sandboxd}}"

    pi_sandbox_log() { printf 'pi: sandbox: %s\n' "$*" >&2; }
    pi_sandbox_die() { printf 'pi: sandbox: %s\n' "$*" >&2; exit 1; }

    pi_sandbox_sweep_stale() {
      find /var/tmp -maxdepth 1 -name "pi-sandbox-$(id -u).*" -type d -user "$(id -u)" -mmin +720 \
        -exec rm -rf {} + 2>/dev/null || true
    }

    # System roots, and anything that contains $HOME, are never mounted: they
    # would expose credentials or trivially escalate to root (nix daemon socket,
    # docker socket, /etc/shadow, other users' homes).
    pi_sandbox_check_mount_root() {
      local root="$1"
      case "$root" in
        / | /home | /root | /nix | /nix/store | /nix/var | /etc | /usr | /var | /run | /tmp | /boot | /dev | /proc | /sys)
          pi_sandbox_die "refusing to mount $root; run Pi from a project directory, or use -insecure"
          ;;
      esac
      case "$HOME/" in
        "$root"/*)
          # $HOME itself is a broad mount (warned about below), but an ancestor of
          # it exposes other homes and system paths.
          if [ "$root" != "$HOME" ]; then
            pi_sandbox_die "refusing to mount $root because it contains $HOME; run Pi from a project directory, or use -insecure"
          fi
          ;;
      esac
    }

    # A mount is "broad" when it is the home directory itself or contains any
    # masked path, i.e. when it exposes data the mask list exists to protect.
    pi_sandbox_is_broad() {
      local root="$1" entry
      [ "$root" = "$HOME" ] && return 0
      for entry in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
        case "$HOME/$entry/" in
          "$root"/*) return 0 ;;
        esac
      done
      return 1
    }

    pi_sandbox_warn_broad() {
      local root="$1" entry
      printf 'pi: sandbox: WARNING: %s is a broad mount.\n' "$root" >&2
      printf 'pi: sandbox:   the agent can read everything under it except:\n' >&2
      for entry in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
        [ -e "$HOME/$entry" ] || continue
        case "$HOME/$entry/" in
          "$root"/*) printf 'pi: sandbox:     %s (masked)\n' "$HOME/$entry" >&2 ;;
        esac
      done
      if [ "''${PI_SANDBOX_NET:-1}" = "1" ]; then
        printf 'pi: sandbox:   network is enabled, so anything it reads can leave this machine.\n' >&2
      fi
      printf 'pi: sandbox:   prefer a project directory, -cwdro for review, or -local for sensitive work.\n' >&2
    }

    pi_sandbox_confirm_broad() {
      local answer
      if [ "''${PI_SANDBOX_ASSUME_YES:-0}" = "1" ]; then
        pi_sandbox_log "continuing with broad mount (-yes)"
        return 0
      fi
      if [ -t 0 ] && [ -t 2 ]; then
        read -r -p "pi: sandbox: continue with this broad mount? [y/N] " answer
        case "$answer" in
          y | Y | yes | YES) return 0 ;;
        esac
        pi_sandbox_die "aborted"
      fi
      pi_sandbox_die "refusing a broad mount without a terminal; pass -yes to accept, or -insecure"
    }

    # Emit docker mount arguments that mask sensitive host paths inside a mount.
    pi_sandbox_compute_mounts() {
      local root="$1" scratch="$2" out="$3"
      : > "$out"
      [ -n "$root" ] || return 0
      : > "$scratch/.mask-empty"
      local entry other abs skip
      for entry in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
        abs="$HOME/$entry"
        [ -e "$abs" ] || continue
        case "$abs/" in
          "$root"/*) ;;
          *) continue ;;
        esac
        skip=0
        for other in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
          [ "$other" = "$entry" ] && continue
          case "$entry" in "$other"/*) skip=1 ;; esac
        done
        [ "$skip" = "1" ] && continue
        if [ -d "$abs" ]; then
          printf -- '--tmpfs\n%s\n' "$abs:rw,size=1m,mode=0700" >> "$out"
        else
          printf -- '-v\n%s:%s:ro\n' "$scratch/.mask-empty" "$abs" >> "$out"
        fi
      done
    }

    pi_sandbox_detect_rootless() {
      local options
      options="$("$PI_SANDBOX_DOCKER" info --format '{{json .SecurityOptions}}' 2>/dev/null || true)"
      case "$options" in
        *rootless*) return 0 ;;
      esac
      return 1
    }

    # Prefer the rootless daemon when it is available: container root maps to the
    # invoking user, so apk works without writing root-owned files to the host.
    # The user's other Docker usage is unaffected because this is exported only
    # for sandbox runs.
    pi_sandbox_select_docker() {
      local sock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
      if [ -z "''${DOCKER_HOST:-}" ] && [ -S "$sock" ]; then
        export DOCKER_HOST="unix://$sock"
      fi
    }

    pi_sandbox_ensure_image() {
      "$PI_SANDBOX_DOCKER" info >/dev/null 2>&1 \
        || pi_sandbox_die "cannot reach the Docker daemon; start Docker or use -insecure"
      "$PI_SANDBOX_DOCKER" image inspect "$PI_SANDBOX_IMAGE" >/dev/null 2>&1 && return 0
      pi_sandbox_log "loading sandbox image $PI_SANDBOX_IMAGE"
      (
        flock 9
        "$PI_SANDBOX_DOCKER" image inspect "$PI_SANDBOX_IMAGE" >/dev/null 2>&1 && exit 0
        "$PI_SANDBOX_DOCKER" load < "$PI_SANDBOX_IMAGE_TAR" >/dev/null
      ) 9>"''${XDG_RUNTIME_DIR:-/tmp}/pi-sandbox-image.lock" \
        || pi_sandbox_die "failed to load the sandbox image"
    }

    # `-copy`: run against a private copy of the project, mounting nothing from
    # the host. Masked paths are excluded so credentials are not copied in.
    pi_sandbox_seed_copy() {
      local root="$1" work="$2" entry excludes=()
      mkdir -p "$work"
      for entry in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
        [ -e "$root/$entry" ] || continue
        excludes+=(--exclude="./$entry")
      done
      pi_sandbox_log "copying $root into the sandbox (no host mount)"
      if ! "$PI_SANDBOX_TAR" -C "$root" -cf - "''${excludes[@]}" . 2>/dev/null \
        | "$PI_SANDBOX_TAR" -C "$work" -xf - 2>/dev/null; then
        pi_sandbox_die "failed to copy $root into the sandbox"
      fi
    }

    # Populate PI_SANDBOX_* for one run. Expects PI_SANDBOX_MODE and
    # PI_SANDBOX_NET to be set by the caller.
    pi_sandbox_prepare() {
      if [ "''${PI_SANDBOX_PREPARED:-0}" = "1" ]; then
        return 0
      fi

      local mount_root
      mount_root="$(realpath -- "$PWD")"
      pi_sandbox_select_docker

      PI_SANDBOX_CWD=""
      PI_SANDBOX_WORKDIR="/tmp"
      case "$PI_SANDBOX_MODE" in
        rw | ro)
          pi_sandbox_check_mount_root "$mount_root"
          if pi_sandbox_is_broad "$mount_root"; then
            pi_sandbox_warn_broad "$mount_root"
            pi_sandbox_confirm_broad
          fi
          PI_SANDBOX_CWD="$mount_root"
          PI_SANDBOX_WORKDIR="$mount_root"
          ;;
        copy)
          pi_sandbox_check_mount_root "$mount_root"
          PI_SANDBOX_WORKDIR="/tmp/work"
          ;;
        none) ;;
        *) pi_sandbox_die "unknown mode: $PI_SANDBOX_MODE" ;;
      esac

      pi_sandbox_sweep_stale
      PI_SANDBOX_SCRATCH="$(mktemp -d "/var/tmp/pi-sandbox-$(id -u).XXXXXXXX")"
      chmod 700 "$PI_SANDBOX_SCRATCH"
      mkdir -p "$PI_SANDBOX_SCRATCH/home" "$PI_SANDBOX_SCRATCH/host-tmp"

      PI_SANDBOX_MOUNT_ARGS_FILE="$PI_SANDBOX_SCRATCH/.mount-args"
      pi_sandbox_compute_mounts "''${PI_SANDBOX_CWD:-}" "$PI_SANDBOX_SCRATCH" "$PI_SANDBOX_MOUNT_ARGS_FILE"

      if [ "$PI_SANDBOX_MODE" = "copy" ]; then
        pi_sandbox_seed_copy "$mount_root" "$PI_SANDBOX_SCRATCH/work"
      fi

      # Give tools a writable home and a git identity that does not depend on the
      # (masked) host configuration.
      printf '[user]\n\tname = %s\n\temail = %s\n[safe]\n\tdirectory = *\n' \
        ${lib.escapeShellArg cfg.gitIdentity.name} ${lib.escapeShellArg cfg.gitIdentity.email} \
        > "$PI_SANDBOX_SCRATCH/home/.gitconfig"

      PI_SANDBOX_DOCKER_USER=""
      if pi_sandbox_detect_rootless; then
        PI_SANDBOX_APK="1"
      else
        PI_SANDBOX_APK="0"
        PI_SANDBOX_DOCKER_USER="$(id -u):$(id -g)"
        pi_sandbox_log "Docker is not rootless; running as $(id -u):$(id -g) (apk installs unavailable)"
      fi

      PI_SANDBOX_PATH="${sandboxBinPath}:/run/current-system/sw/bin"
      local profile
      profile="$(readlink -f "/etc/profiles/per-user/$(id -un)" 2>/dev/null || true)"
      if [ -n "$profile" ] && [ -d "$profile/bin" ]; then
        PI_SANDBOX_PATH="$PI_SANDBOX_PATH:$profile/bin"
      fi
      if [ -d "$HOME/.nix-profile/bin" ]; then
        PI_SANDBOX_PATH="$PI_SANDBOX_PATH:$HOME/.nix-profile/bin"
      fi
      PI_SANDBOX_PATH="$PI_SANDBOX_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

      export PI_SANDBOX_CWD PI_SANDBOX_WORKDIR PI_SANDBOX_SCRATCH PI_SANDBOX_MOUNT_ARGS_FILE
      export PI_SANDBOX_DOCKER_USER PI_SANDBOX_APK PI_SANDBOX_PATH PI_SANDBOX_PREPARED=1
      export PI_SANDBOX_CMD="$PI_SANDBOX_EXEC"
      export TMPDIR="$PI_SANDBOX_SCRATCH/host-tmp"
    }

    pi_sandbox_cleanup() {
      [ -n "''${PI_SANDBOX_SCRATCH:-}" ] || return 0
      [ -d "$PI_SANDBOX_SCRATCH" ] || return 0
      rm -rf "$PI_SANDBOX_SCRATCH"
    }
  '';

  # Runs a command inside a fresh sandbox container. The extension spawns
  # `pi-sandbox-exec sandboxd`; the helper commands run a shell instead.
  sandboxExec = pkgs.writeShellScriptBin "pi-sandbox-exec" ''
    set -euo pipefail
    source ${sandboxLib}

    PI_SANDBOX_EXEC="$0"
    export PI_SANDBOX_EXEC

    if [ "''${PI_SANDBOX_PREPARED:-0}" != "1" ]; then
      PI_SANDBOX_MODE="''${PI_SANDBOX_MODE:-none}"
      PI_SANDBOX_NET="''${PI_SANDBOX_NET:-1}"
      export PI_SANDBOX_MODE PI_SANDBOX_NET
      pi_sandbox_prepare
      trap pi_sandbox_cleanup EXIT
    fi
    pi_sandbox_ensure_image

    entry=()
    if [ "''${1:-sandboxd}" = "sandboxd" ]; then
      entry=("$PI_SANDBOX_NODE" "$PI_SANDBOX_SANDBOXD")
    else
      [ "''${1:-}" = "--" ] && shift
      entry=("$@")
    fi
    [ "''${#entry[@]}" -gt 0 ] || pi_sandbox_die "pi-sandbox-exec: no command given"

    args=(
      run --rm --interactive --init
      --name "pi-sandbox-$$"
      --label pi-sandbox=1
      --security-opt no-new-privileges
      --pids-limit ${toString cfg.limits.pids}
      --memory ${cfg.limits.memory}
      --cpus ${toString cfg.limits.cpus}
      --workdir "$PI_SANDBOX_WORKDIR"
    )
    if [ "''${PI_SANDBOX_NET:-1}" = "0" ]; then
      args+=(--network none)
    fi
    if [ -n "$PI_SANDBOX_DOCKER_USER" ]; then
      args+=(--user "$PI_SANDBOX_DOCKER_USER")
    fi
    if [ -t 0 ] && [ -t 1 ]; then
      args+=(--tty)
    fi
    args+=(
      -v "$PI_SANDBOX_SCRATCH:/tmp"
      -v "$PI_SANDBOX_SCRATCH:$PI_SANDBOX_SCRATCH"
      -v /nix/store:/nix/store:ro
      -v /nix/var/nix/profiles:/nix/var/nix/profiles:ro
      -v /run/current-system/sw/bin:/run/current-system/sw/bin:ro
    )
    if [ -n "$PI_SANDBOX_CWD" ]; then
      if [ "$PI_SANDBOX_MODE" = "rw" ]; then
        args+=(-v "$PI_SANDBOX_CWD:$PI_SANDBOX_CWD")
      else
        args+=(-v "$PI_SANDBOX_CWD:$PI_SANDBOX_CWD:ro")
      fi
    fi
    while IFS= read -r mount_arg; do
      [ -n "$mount_arg" ] && args+=("$mount_arg")
    done < "$PI_SANDBOX_MOUNT_ARGS_FILE"
    args+=(
      -e HOME=/tmp/home
      -e TMPDIR=/tmp
      -e XDG_CACHE_HOME=/tmp/home/.cache
      -e UV_CACHE_DIR=/tmp/home/.cache/uv
      -e "PATH=$PI_SANDBOX_PATH"
      -e "SANDBOX_SHELL=$PI_SANDBOX_BASH"
      -e "SSL_CERT_FILE=${cacertBundle}"
      -e "NIX_SSL_CERT_FILE=${cacertBundle}"
      -e GIT_OPTIONAL_LOCKS=0
      -e PYTHONDONTWRITEBYTECODE=1
      -e "TERM=''${TERM:-xterm-256color}"
      -e "LANG=''${LANG:-C.UTF-8}"
      # Alpine's /etc/profile resets PATH, so record the sandbox tool path in
      # /etc/profile.d before handing over to the real entry point. Doing it here
      # keeps login shells (including pi-sandbox-shell) consistent. It is
      # best-effort: with the non-rootless fallback the container user cannot
      # write /etc, and login shells then keep Alpine's default PATH.
      --entrypoint /bin/sh
      "$PI_SANDBOX_IMAGE"
      -c 'mkdir -p /etc/profile.d 2>/dev/null
( printf "export PATH=%s:\"\$PATH\"\n" "$PATH" > /etc/profile.d/10-pi-sandbox-path.sh ) 2>/dev/null
exec "$@"' pi-sandbox
    )
    args+=("''${entry[@]}")

    exec "$PI_SANDBOX_DOCKER" "''${args[@]}"
  '';

  # Interactive shell with exactly the sandbox mounts, for debugging.
  sandboxShell = pkgs.writeShellScriptBin "pi-sandbox-shell" ''
    set -euo pipefail
    source ${sandboxLib}

    PI_SANDBOX_MODE="none"
    PI_SANDBOX_NET="1"
    PI_SANDBOX_ASSUME_YES=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -cwd) PI_SANDBOX_MODE="rw" ;;
        -cwdro) PI_SANDBOX_MODE="ro" ;;
        -copy) PI_SANDBOX_MODE="copy" ;;
        -local) PI_SANDBOX_NET="0" ;;
        -yes) PI_SANDBOX_ASSUME_YES=1 ;;
        *) break ;;
      esac
      shift
    done
    PI_SANDBOX_EXEC="${sandboxExec}/bin/pi-sandbox-exec"
    export PI_SANDBOX_MODE PI_SANDBOX_NET PI_SANDBOX_ASSUME_YES PI_SANDBOX_EXEC

    pi_sandbox_prepare
    trap pi_sandbox_cleanup EXIT
    pi_sandbox_log "scratch: $PI_SANDBOX_SCRATCH"
    # --noprofile keeps the sandbox PATH: Alpine's /etc/profile would reset it to
    # the busybox default when the container cannot write /etc/profile.d.
    "$PI_SANDBOX_EXEC" -- "$PI_SANDBOX_BASH" --noprofile -l
  '';

  # Probe suite: verifies the isolation claims for each mode.
  sandboxDoctor = pkgs.writeShellScriptBin "pi-sandbox-doctor" ''
    set -uo pipefail
    source ${sandboxLib}

    mode="''${1:-none}"
    case "$mode" in
      none | ro | rw | copy) ;;
      *) printf 'usage: pi-sandbox-doctor [none|ro|rw|copy]  (PI_SANDBOX_DOCTOR_NET=0 for offline)\n' >&2; exit 2 ;;
    esac
    net="''${PI_SANDBOX_DOCTOR_NET:-1}"

    PI_SANDBOX_MODE="$mode"
    PI_SANDBOX_NET="$net"
    PI_SANDBOX_ASSUME_YES=1
    PI_SANDBOX_EXEC="${sandboxExec}/bin/pi-sandbox-exec"
    export PI_SANDBOX_MODE PI_SANDBOX_NET PI_SANDBOX_ASSUME_YES PI_SANDBOX_EXEC

    pi_sandbox_prepare
    trap pi_sandbox_cleanup EXIT

    failures=0
    probe() {
      local description="$1" command="$2"
      if "$PI_SANDBOX_EXEC" -- "$PI_SANDBOX_BASH" -c "$command" >/dev/null 2>&1; then
        printf '  PASS  %s\n' "$description"
      else
        printf '  FAIL  %s\n' "$description"
        failures=$((failures + 1))
      fi
    }

    printf 'pi-sandbox-doctor: mode=%s net=%s\n' "$mode" "$net"
    printf '  docker rootless: %s\n' "$(pi_sandbox_detect_rootless && echo yes || echo no)"
    printf '  scratch: %s\n' "$PI_SANDBOX_SCRATCH"

    printf '\nisolation\n'
    probe "host Pi credentials are not visible" "test ! -e '$HOME/.pi/agent/auth.json'"
    probe "no docker socket" "test ! -e /var/run/docker.sock"
    probe "no nix daemon socket" "test ! -e /nix/var/nix/daemon-socket/socket"
    probe "no host environment secrets" "! env | grep -qiE 'api_?key|token|secret|password'"
    probe "no PI_SESSION_FILE leak" "test -z \"\''${PI_SESSION_FILE:-}\""
    probe "pid namespace is private" "test \"\$(ls /proc | grep -cE '^[0-9]+\$')\" -lt 40"
    probe "no docker CLI socket access" "! docker ps"
    probe "/nix/store is readable" "test -r /nix/store"
    probe "/nix/store is read-only" "! touch /nix/store/.pi-sandbox-probe"

    printf '\nmasks\n'
    masked=0
    for entry in "''${PI_SANDBOX_MASK_PATHS[@]}"; do
      abs="$HOME/$entry"
      [ -e "$abs" ] || continue
      [ -n "$PI_SANDBOX_CWD" ] || continue
      case "$abs/" in
        "$PI_SANDBOX_CWD"/*) ;;
        *) continue ;;
      esac
      masked=1
      if [ -d "$abs" ]; then
        probe "$entry is masked" "test -z \"\$(ls -A '$abs' 2>/dev/null)\""
      else
        probe "$entry is masked" "test ! -s '$abs'"
      fi
    done
    [ "$masked" = "1" ] || printf '  SKIP  no masked paths inside the mount\n'

    printf '\nmode\n'
    case "$mode" in
      rw)
        probe "cwd is writable" "touch '$PWD/.pi-sandbox-probe' && rm -f '$PWD/.pi-sandbox-probe'"
        ;;
      ro)
        probe "cwd is readable" "test -r '$PWD'"
        probe "cwd is read-only" "! touch '$PWD/.pi-sandbox-probe'"
        ;;
      copy)
        probe "workdir is the private copy" "test \"\$(pwd)\" = /tmp/work"
        probe "copy is writable" "touch /tmp/work/.pi-sandbox-probe"
        ;;
      none)
        probe "workdir is /tmp" "test \"\$(pwd)\" = /tmp"
        ;;
    esac
    probe "scratch is writable" "touch /tmp/.pi-sandbox-probe"
    probe "scratch is private" "test \"\$(stat -c %a /tmp)\" = 700"

    printf '\nnetwork\n'
    if [ "$net" = "1" ]; then
      probe "internet reachable" "curl -sS --max-time 10 -o /dev/null https://example.com"
    else
      probe "internet blocked" "! curl -sS --max-time 5 -o /dev/null https://example.com"
      probe "dns blocked" "! getent hosts example.com"
    fi

    printf '\ntools\n'
    probe "bash available" "bash --version"
    probe "ripgrep available" "rg --version"
    probe "fd available" "fd --version"
    probe "git available" "git --version"
    probe "python3 available" "python3 -c 'import threading'"
    probe "uv available" "uv --version"
    probe "node available" "node -e 'require(\"worker_threads\")'"
    probe "apk available" "test -x /sbin/apk"

    printf '\n'
    if [ "$failures" -eq 0 ]; then
      printf 'all checks passed\n'
    else
      printf '%s check(s) failed\n' "$failures"
      exit 1
    fi
  '';

  # The `pi` entry point: parses sandbox flags, prepares the run and starts Pi
  # with the sandbox extension force-loaded and built-in tools disabled.
  piLauncher = pkgs.writeShellScriptBin "pi" ''
    set -euo pipefail
    source ${sandboxLib}

    # Run Pi at low priority in the agent slice; see ../agent-slice.nix.
    if [[ -z "''${PI_AGENT_SLICE:-}" && -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
      export PI_AGENT_SLICE=1
      exec ${agentSlice.systemdRun} "$0" "$@"
    fi

    pi_bin=${pkgs.pi-coding-agent}/bin/pi

    # Package/auth subcommands and informational flags never run tools.
    case "''${1:-}" in
      install | remove | uninstall | update | list | config | auth | \
        --help | -h | --version | -v | --list-models | --export)
        exec "$pi_bin" "$@"
        ;;
    esac

    PI_SANDBOX_MODE="${cfg.defaultMode}"
    PI_SANDBOX_NET="1"
    PI_SANDBOX_ASSUME_YES=0
    explicit_mode=0
    explicit_local=0
    insecure=0
    passthrough=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -cwd | --cwd) PI_SANDBOX_MODE="rw"; explicit_mode=1 ;;
        -cwdro | --cwdro) PI_SANDBOX_MODE="ro"; explicit_mode=1 ;;
        -copy | --copy) PI_SANDBOX_MODE="copy"; explicit_mode=1 ;;
        -local | --local) PI_SANDBOX_NET="0"; explicit_local=1 ;;
        -insecure | --insecure) insecure=1 ;;
        -yes | --yes) PI_SANDBOX_ASSUME_YES=1 ;;
        --)
          passthrough+=("$@")
          break
          ;;
        *)
          passthrough+=("$1")
          ;;
      esac
      shift
    done

    if [ "$insecure" = "1" ]; then
      if [ "$explicit_mode" = "1" ] || [ "$explicit_local" = "1" ]; then
        pi_sandbox_die "-insecure cannot be combined with -cwd, -cwdro, -copy or -local"
      fi
      exec "$pi_bin" "''${passthrough[@]}"
    fi

    export PI_SANDBOX_MODE PI_SANDBOX_NET PI_SANDBOX_ASSUME_YES
    export PI_SANDBOX_STRICT="${if cfg.strictTools then "1" else "0"}"
    export PI_SANDBOX_EXEC="${sandboxExec}/bin/pi-sandbox-exec"

    # Host-side extensions (for example the Brave search one) run outside the
    # container's network namespace, so `--network none` cannot stop them.
    # -local therefore disables them explicitly with PI_WEB=0; the value is
    # otherwise inherited from the environment, so PI_WEB=0 works everywhere.
    PI_WEB="''${PI_WEB:-1}"
    if [ "$PI_SANDBOX_NET" = "0" ]; then PI_WEB=0; fi
    export PI_WEB

    pi_sandbox_prepare
    pi_sandbox_ensure_image
    trap pi_sandbox_cleanup EXIT

    if [ -n "$PI_SANDBOX_CWD" ]; then
      pi_sandbox_log "mode=$PI_SANDBOX_MODE net=$PI_SANDBOX_NET cwd=$PI_SANDBOX_CWD scratch=$PI_SANDBOX_SCRATCH"
    else
      pi_sandbox_log "mode=$PI_SANDBOX_MODE net=$PI_SANDBOX_NET scratch=$PI_SANDBOX_SCRATCH"
    fi

    "$pi_bin" -e ${extension} -nbt "''${passthrough[@]}"
  '';
in
{
  options.my.piSandbox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Route Pi's built-in tools into a Docker container. Disabling this falls
        back to the plain launcher, which runs every tool with host permissions.
      '';
    };

    defaultMode = lib.mkOption {
      type = lib.types.enum [
        "none"
        "ro"
        "rw"
      ];
      default = "none";
      description = ''
        Mount mode used when `pi` is started without `-cwd`, `-cwdro` or `-copy`.
        `none` mounts only the ephemeral scratch directory; `ro` and `rw` mount
        the working directory read-only or read-write.
      '';
    };

    imageName = lib.mkOption {
      type = lib.types.str;
      default = "pi-sandbox-alpine";
      description = "Local Docker image name for the sandbox image.";
    };

    imageTag = lib.mkOption {
      type = lib.types.str;
      default = "3.24.2";
      description = "Local Docker image tag for the sandbox image.";
    };

    strictTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When enabled, tool calls other than the sandboxed built-ins (for example
        MCP or project-extension tools, which run on the host) are blocked.
      '';
    };

    gitIdentity = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Pi Sandbox";
        description = "`user.name` written to the sandbox git configuration.";
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "pi-sandbox@localhost";
        description = "`user.email` written to the sandbox git configuration.";
      };
    };

    limits = {
      memory = lib.mkOption {
        type = lib.types.str;
        default = "8g";
        description = "Container memory limit.";
      };
      cpus = lib.mkOption {
        type = lib.types.either lib.types.int lib.types.float;
        default = 4;
        description = "Container CPU limit.";
      };
      pids = lib.mkOption {
        type = lib.types.int;
        default = 2048;
        description = "Container process limit.";
      };
    };

    maskPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = maskPaths;
      description = ''
        Home-relative paths hidden from any mounted directory. Directories are
        replaced with an empty tmpfs and files with an empty read-only file, so a
        broad mount such as the home directory cannot expose credentials or
        host-persistence vectors.
      '';
    };

    launcher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "The sandbox-aware `pi` launcher.";
    };

    extension = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      internal = true;
      description = "Sandbox tool-routing extension loaded by the launcher.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.piSandbox.launcher = piLauncher;
    my.piSandbox.extension = extension;

    home.packages = [
      sandboxShell
      sandboxDoctor
    ];

    home.file.".local/share/pi-sandbox/README.md".source = ./README.md;
  };
}
