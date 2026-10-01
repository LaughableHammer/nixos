{
  pkgs ? import <nixpkgs> { },
}:

let
  fakeAgent = pkgs.writeShellScriptBin "pi" ''
    set -euo pipefail

    if [[ "''${PI_CWD_CONFINED:-}" != 1 ]]; then
      printf '%s\0' "$@" > "$PI_TEST_LOG"
      exit 0
    fi

    [[ "$#" == 2 ]]
    [[ "$1" == "--continue" ]]
    [[ "$2" == "payload" ]]
    [[ "$HOME" == "$PWD/.pi-confined/home" ]]
    [[ "$PI_CODING_AGENT_DIR" == "$PWD/.pi-confined/agent" ]]
    [[ "$PI_CODING_AGENT_SESSION_DIR" == "$PWD/.pi-confined/sessions" ]]

    [[ "$(cat readable)" == inside ]]
    printf writable > written
    [[ ! -e ../parent-secret ]]
    [[ ! -e ../sibling/secret ]]
    [[ ! -e "$PI_TEST_OUTSIDE" ]]
    [[ ! -e external-link ]]
    [[ ! -r /etc/passwd ]]
    if printf bad > ../escape 2>/dev/null; then
      echo "writing outside the cwd unexpectedly succeeded" >&2
      exit 1
    fi

    bash -c 'set -eu; test ! -r /etc/passwd; test ! -e ../parent-secret; printf child > child-written'
    git --version >/dev/null
    rg --version >/dev/null
    node --version >/dev/null
    printf confined > confinement-passed
  '';

  wrapper = import ../cwd-confined-wrapper.nix {
    inherit pkgs;
    pi-coding-agent = fakeAgent;
  };
in
pkgs.runCommand "pi-cwd-confined-launcher-test"
  {
    nativeBuildInputs = [ wrapper ];
  }
  ''
    set -euo pipefail

    mkdir -p "$TMPDIR/parent/project" "$TMPDIR/parent/sibling"
    printf inside > "$TMPDIR/parent/project/readable"
    printf parent > "$TMPDIR/parent/parent-secret"
    printf sibling > "$TMPDIR/parent/sibling/secret"
    ln -s "$TMPDIR/parent/sibling/secret" "$TMPDIR/parent/project/external-link"

    # No -cwd: preserve every argument, including both upstream continue forms,
    # byte-for-byte.
    export PI_TEST_LOG="$TMPDIR/unconfined-args"
    pi -c --continue -cfoo
    printf '%s\0' -c --continue -cfoo > "$TMPDIR/expected-args"
    cmp "$TMPDIR/expected-args" "$PI_TEST_LOG"

    # Exact -cwd: remove only that token and run all descendants in Bubblewrap.
    export PI_TEST_OUTSIDE="$TMPDIR/parent/sibling/secret"
    cd "$TMPDIR/parent/project"
    pi --continue -cwd payload

    test -f written
    test -f child-written
    test -f confinement-passed
    test -d .pi-confined/home
    test -d .pi-confined/agent
    test -d .pi-confined/sessions
    test ! -e ../escape

    touch "$out"
  ''
