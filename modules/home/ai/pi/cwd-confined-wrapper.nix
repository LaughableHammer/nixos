{
  pkgs,
  pi-coding-agent ? pkgs.pi-coding-agent,
  confinedConfig ? null,
}:

let
  agentSlice = import ./agent-slice.nix { inherit pkgs; };

  # Deliberately small command set. Its complete runtime closure is mounted
  # read-only; no user profile or host PATH is visible in confined mode.
  sandboxTools = with pkgs; [
    bash
    coreutils
    curl
    fd
    findutils
    git
    gnugrep
    gnused
    gnutar
    gzip
    jq
    nodejs
    ripgrep
  ];

  toolRoot = pkgs.symlinkJoin {
    name = "pi-confined-tools";
    paths = sandboxTools;
  };

  runtimeClosure = pkgs.closureInfo {
    rootPaths = [
      pi-coding-agent
      toolRoot
      pkgs.cacert
    ]
    ++ pkgs.lib.optional (confinedConfig != null) confinedConfig;
  };
in
pkgs.writeShellScriptBin "pi" ''
  set -euo pipefail

  # Run at low priority in the agent slice; see agent-slice.nix.
  if [[ -z "''${PI_AGENT_SLICE:-}" && -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
    export PI_AGENT_SLICE=1
    exec ${agentSlice.systemdRun} "$0" "$@"
  fi

  confined=false
  piArgs=()
  for arg in "$@"; do
    if [[ "$arg" == "-cwd" ]]; then
      confined=true
    else
      piArgs+=("$arg")
    fi
  done

  # In normal mode this is a transparent exec. In particular, -c and
  # --continue are neither rewritten nor interpreted by this launcher.
  if ! "$confined"; then
    exec ${pi-coding-agent}/bin/pi "$@"
  fi

  physicalCwd=$(pwd -P)
  confinedRoot="$physicalCwd/.pi-confined"
  agentDir="$confinedRoot/agent"
  sessionDir="$confinedRoot/sessions"

  ${pkgs.coreutils}/bin/mkdir -p \
    "$confinedRoot/home" \
    "$agentDir/extensions" \
    "$sessionDir"

  ${pkgs.lib.optionalString (confinedConfig != null) ''
    # Refresh declarative config on every launch so it tracks this repo;
    # sessions and other state remain untouched.
    for file in settings.json models.json SYSTEM.md; do
      ${pkgs.coreutils}/bin/cp ${confinedConfig}/"$file" "$agentDir/$file"
    done
    ${pkgs.coreutils}/bin/ln -sfn \
      ${confinedConfig}/extensions/cwd-confined.ts \
      "$agentDir/extensions/cwd-confined.ts"
  ''}

  bwrapArgs=(
    --die-with-parent
    --new-session
    --unshare-pid
    --unshare-ipc
    --unshare-uts
    --cap-drop ALL
    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --dir /nix
    --dir /nix/store
    --dir /etc
    --dir /etc/ssl
    --dir /etc/ssl/certs
  )

  # Bubblewrap starts with an empty root. Create only the cwd's parent chain,
  # then place the physical cwd at its original absolute path.
  parent="$physicalCwd"
  parents=()
  while [[ "$parent" != "/" ]]; do
    parent=$(${pkgs.coreutils}/bin/dirname "$parent")
    [[ "$parent" == "/" ]] || parents=("$parent" "''${parents[@]}")
  done
  for parent in "''${parents[@]}"; do
    bwrapArgs+=(--dir "$parent")
  done
  bwrapArgs+=(--dir "$physicalCwd")
  bwrapArgs+=(--bind "$physicalCwd" "$physicalCwd")

  # Mount only the runtime closure rather than all of /nix/store.
  while IFS= read -r storePath; do
    bwrapArgs+=(--ro-bind "$storePath" "$storePath")
  done < ${runtimeClosure}/store-paths

  # Resolver state and a single CA bundle are the only /etc exceptions.
  bwrapArgs+=(
    --ro-bind ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
  )
  if [[ -e /etc/resolv.conf ]]; then
    bwrapArgs+=(--ro-bind /etc/resolv.conf /etc/resolv.conf)
  fi
  if [[ -e /etc/hosts ]]; then
    hostsPath=$(${pkgs.coreutils}/bin/readlink -f /etc/hosts)
    bwrapArgs+=(--ro-bind "$hostsPath" /etc/hosts)
  fi

  # Make the empty root and cwd parent placeholders read-only so ../ writes
  # fail rather than landing in throwaway sandbox storage. This remount is not
  # recursive: the cwd bind, /tmp, /dev, and /proc remain writable as intended.
  bwrapArgs+=(--remount-ro /)

  # The network namespace remains shared intentionally. Environment variables
  # are inherited so provider keys, custom endpoints, and proxy settings work;
  # filesystem credential stores are not mounted.
  exec ${pkgs.bubblewrap}/bin/bwrap "''${bwrapArgs[@]}" \
    --setenv HOME "$confinedRoot/home" \
    --setenv PI_CODING_AGENT_DIR "$agentDir" \
    --setenv PI_CODING_AGENT_SESSION_DIR "$sessionDir" \
    --setenv PI_CWD_CONFINED 1 \
    --setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt \
    --setenv GIT_SSL_CAINFO /etc/ssl/certs/ca-certificates.crt \
    --setenv PATH ${toolRoot}/bin:${pi-coding-agent}/bin \
    --chdir "$physicalCwd" \
    ${pi-coding-agent}/bin/pi "''${piArgs[@]}"
''
