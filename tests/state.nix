{
  runCommandLocal,
  writeText,
  git,
  vuh,
}:

let
  config = writeText "single-module.vuh" ''
    MAIN_BRANCH_NAME='main'
    VERSION_FILE='version.sh'
    TEXT_BEFORE_VERSION_CODE="VERSION='"
    TEXT_AFTER_VERSION_CODE="'"
  '';
in
# Only meaningful for a build with `enableUpdateChecks = true`: the daily check
# is the one thing in vuh that writes at runtime. It has to write to the state
# directory (never to the store) and it has to survive having no network, which
# is exactly the situation inside this sandbox.
runCommandLocal "vuh-test-state"
  {
    nativeBuildInputs = [
      git
      vuh
    ];
  }
  ''
    set -euo pipefail

    export HOME="$NIX_BUILD_TOP/home"
    mkdir -p "$HOME"
    git config --global user.name 'vuh test'
    git config --global user.email 'vuh@example.invalid'
    git config --global init.defaultBranch main

    git init -q project
    cd project
    cp ${config} .vuh
    echo "VERSION='1.2.3'" > version.sh
    git add .
    git commit -qm 'initial'

    stamp() { echo "$1/vuh/latest_update_check"; }

    # 1. XDG default. Not quiet, not offline: the update check runs, fails to
    #    reach github, and must not take the command down with it.
    export XDG_STATE_HOME="$NIX_BUILD_TOP/state"
    output=$(vuh lv --dont-use-git 2>&1)
    case "$output" in
      *'local: 1.2.3'*) echo 'ok: the command still works without network' ;;
      *)
        echo 'FAIL: an unreachable github broke an unrelated command:' >&2
        printf '%s\n' "$output" >&2
        exit 1
        ;;
    esac

    [ -f "$(stamp "$XDG_STATE_HOME")" ] ||
      { echo "FAIL: no update stamp under XDG_STATE_HOME" >&2; exit 1; }
    grep -qE '^[0-9]{4}-[0-9]+$' "$(stamp "$XDG_STATE_HOME")" ||
      { echo 'FAIL: the update stamp does not look like a date' >&2; exit 1; }
    echo 'ok: state goes to $XDG_STATE_HOME/vuh'

    # 2. VUH_STATE_DIR wins over the XDG default.
    VUH_STATE_DIR="$NIX_BUILD_TOP/explicit-state" vuh lv --dont-use-git > /dev/null 2>&1
    [ -f "$NIX_BUILD_TOP/explicit-state/latest_update_check" ] ||
      { echo 'FAIL: VUH_STATE_DIR was ignored' >&2; exit 1; }
    echo 'ok: VUH_STATE_DIR is honoured'

    # 3. Nothing was written next to the installed script.
    if [ -e ${vuh}/share/vuh/latest_update_check ]; then
      echo 'FAIL: vuh wrote into its own (read-only) installation directory' >&2
      exit 1
    fi
    echo 'ok: the store was left alone'

    touch "$out"
  ''
