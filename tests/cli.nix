{
  lib,
  runCommandLocal,
  writeText,
  git,
  vuh,
}:

let
  singleModuleConfig = writeText "single-module.vuh" ''
    MAIN_BRANCH_NAME='main'
    VERSION_FILE='version.sh'
    TEXT_BEFORE_VERSION_CODE="VERSION='"
    TEXT_AFTER_VERSION_CODE="'"
    MODULE_ROOT_PATH=""
    IS_INCREMENT_REQUIRED_ONLY_ON_CHANGES='false'
    MINOR_CHANGING_LOCATIONS=""
    MAJOR_CHANGING_LOCATIONS=""
  '';

  monoRepoConfig = writeText "mono-repo.vuh" ''
    MAIN_BRANCH_NAME='main'
    VERSION_FILE='api/version.sh'
    TEXT_BEFORE_VERSION_CODE="VERSION='"
    TEXT_AFTER_VERSION_CODE="'"
    MODULE_ROOT_PATH=""
    IS_INCREMENT_REQUIRED_ONLY_ON_CHANGES='false'
    MINOR_CHANGING_LOCATIONS=""
    MAJOR_CHANGING_LOCATIONS=""

    PROJECT_MODULES='API,WEB'

    API_MAIN_BRANCH_NAME='main'
    API_VERSION_FILE='api/version.sh'
    API_TEXT_BEFORE_VERSION_CODE="VERSION='"
    API_TEXT_AFTER_VERSION_CODE="'"
    API_MODULE_ROOT_PATH='api'
    API_MODULE_DESCRIPTION='the API'

    WEB_MAIN_BRANCH_NAME='main'
    WEB_VERSION_FILE='web/version.sh'
    WEB_TEXT_BEFORE_VERSION_CODE="VERSION='"
    WEB_TEXT_AFTER_VERSION_CODE="'"
    WEB_MODULE_ROOT_PATH='web'
    WEB_MODULE_DESCRIPTION='the frontend'
  '';
in
# End-to-end exercise of the commands people actually run, against throwaway git
# repositories with a real "origin" remote.
runCommandLocal "vuh-test-cli"
  {
    nativeBuildInputs = [
      git
      vuh
    ];
  }
  ''
    set -euo pipefail

    export HOME="$NIX_BUILD_TOP/home"
    export XDG_STATE_HOME="$NIX_BUILD_TOP/state"
    mkdir -p "$HOME"

    git config --global user.name 'vuh test'
    git config --global user.email 'vuh@example.invalid'
    git config --global init.defaultBranch main

    assertEq() { # <what> <expected> <actual>
      if [ "$2" != "$3" ]; then
        echo "FAIL: $1: expected '$2', got '$3'" >&2
        exit 1
      fi
      echo "ok: $1 -> $2"
    }

    assertContains() { # <what> <needle> <haystack>
      case "$3" in
        *"$2"*) echo "ok: $1 contains '$2'" ;;
        *)
          echo "FAIL: $1: '$2' not found in:" >&2
          printf '%s\n' "$3" >&2
          exit 1
          ;;
      esac
    }

    ###########################################################################
    # A single module project
    ###########################################################################

    cd "$NIX_BUILD_TOP"
    git init -q --bare origin.git
    git clone -q origin.git project
    cd project

    cp ${singleModuleConfig} .vuh
    echo "VERSION='1.2.3'" > version.sh
    git add . && git commit -qm 'initial'
    git push -q -u origin main

    assertEq 'local-version' '1.2.3' "$(vuh lv -q)"
    assertEq 'main-version'  '1.2.3' "$(vuh mv -q)"

    # Not quiet: goes through the daily-update-check code path, which this build
    # has compiled out. It must stay silent and must not touch the network.
    assertContains 'verbose local-version' 'local: 1.2.3' "$(vuh lv)"

    git checkout -q -b feature
    echo 'a change' > code.txt
    git add . && git commit -qm 'a change'

    assertEq 'suggest-version'       '1.2.4' "$(vuh sv -q)"
    assertEq 'suggest-version minor' '1.3.0' "$(vuh sv -q -vp=minor)"
    assertEq 'suggest-version major' '2.0.0' "$(vuh sv -q -vp=major)"

    assertEq 'update-version'          '1.2.4'           "$(vuh uv -q)"
    assertEq 'version file rewritten'  "VERSION='1.2.4'" "$(cat version.sh)"
    assertEq 'local-version after bump' '1.2.4'          "$(vuh lv -q)"
    # Running it again is a no-op, not a second bump.
    assertEq 'update-version is idempotent' '1.2.4' "$(vuh uv -q)"

    ###########################################################################
    # Working without git, from outside the repository
    ###########################################################################

    cd "$NIX_BUILD_TOP"
    assertEq 'local-version --dont-use-git' '1.2.4' \
      "$(vuh lv -q --dont-use-git --config-dir="$NIX_BUILD_TOP/project")"

    ###########################################################################
    # A mono repository. `-pm=ALL` makes vuh re-invoke itself once per module,
    # which is where a badly built wrapper falls apart.
    ###########################################################################

    cd "$NIX_BUILD_TOP"
    git init -q --bare mono-origin.git
    git clone -q mono-origin.git mono
    cd mono

    mkdir -p api web
    cp ${monoRepoConfig} .vuh
    echo "VERSION='1.0.0'" > api/version.sh
    echo "VERSION='2.0.0'" > web/version.sh
    git add . && git commit -qm 'initial'
    git push -q -u origin main

    assertEq 'project-modules'         'API,WEB' "$(vuh pm -q)"
    assertEq 'local-version -pm=API'   '1.0.0'   "$(vuh lv -q -pm=API)"
    assertEq 'local-version -pm=WEB'   '2.0.0'   "$(vuh lv -q -pm=WEB)"
    assertEq 'module-root-path -pm=API' 'api'    "$(vuh mrp -q -pm=API)"
    # Self-recursion: one line per module, in PROJECT_MODULES order.
    assertEq 'local-version -pm=ALL' '1.0.0 2.0.0' "$(vuh lv -q -pm=ALL | paste -sd' ')"
    # From inside a module directory, without naming the module.
    assertEq 'local-version -cpm' '2.0.0' "$(cd web && vuh lv -q -cpm)"

    ###########################################################################
    # Standalone commands
    ###########################################################################

    assertContains 'help'          'Usage: vuh'                    "$(vuh --help)"
    assertContains 'help'          'update-version'                "$(vuh --help)"
    assertContains 'version'       '${vuh.version}'                "$(vuh --version)"
    assertContains 'configuration' "INSTALLATION_DIR='${vuh}/bin'"  "$(vuh --configuration)"
    assertContains 'configuration' "DAILY_UPDATE_CHECKS='false'"    "$(vuh --configuration)"

    # Self-update is not a thing for a package-manager owned install: it has to
    # fail loudly rather than silently do nothing or try to write to the store.
    if update_out=$(vuh --update 2>&1); then
      echo "FAIL: 'vuh --update' succeeded, expected it to refuse" >&2
      printf '%s\n' "$update_out" >&2
      exit 1
    fi
    assertContains 'update refusal' 'package manager' "$update_out"

    ###########################################################################
    # The wrapper carries every tool vuh needs instead of borrowing them
    ###########################################################################

    cd "$NIX_BUILD_TOP/project"
    assertEq 'runs with an empty PATH' '1.2.4' \
      "$(env -i HOME="$HOME" PATH=/nonexistent ${vuh}/bin/vuh lv -q)"
    assertEq 'runs with an empty PATH (git)' '1.2.3' \
      "$(env -i HOME="$HOME" PATH=/nonexistent ${vuh}/bin/vuh mv -q)"

    ###########################################################################
    # No droppings
    ###########################################################################

    if [ -e /tmp/vuh_projects_conf_file ]; then
      echo 'FAIL: vuh left a predictable temp file behind' >&2
      exit 1
    fi
    echo 'ok: no predictable temp file'

    ${lib.optionalString (!vuh.enableUpdateChecks) ''
      # Update checks are off, so nothing should have been written at all.
      if [ -e "$XDG_STATE_HOME" ]; then
        echo "FAIL: vuh created state in $XDG_STATE_HOME with update checks disabled" >&2
        find "$XDG_STATE_HOME" >&2
        exit 1
      fi
      echo 'ok: no runtime state written'
    ''}

    touch "$out"
  ''
