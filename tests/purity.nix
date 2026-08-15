{
  lib,
  runCommandLocal,
  vuh,
}:

# Static checks on the built package: everything installer.sh would have
# substituted is substituted, and nothing points outside the store.
runCommandLocal "vuh-test-purity" { } ''
  set -euo pipefail

  script=${vuh}/bin/.vuh-wrapped
  wrapper=${vuh}/bin/vuh

  fail() { echo "FAIL: $*" >&2; exit 1; }
  ok() { echo "ok: $*"; }

  [ -x "$wrapper" ] || fail 'no wrapper at $out/bin/vuh'
  [ -x "$script" ] || fail 'no wrapped script at $out/bin/.vuh-wrapped'

  # 1. No leftover installation placeholders.
  if grep -n 'should_be_replace_after_installation' "$script"; then
    fail 'unsubstituted installer placeholder left in vuh.sh'
  fi
  ok 'all installer placeholders substituted'

  # 2. DATA_DIR points at this package's own share directory.
  grep -qF "DATA_DIR='${vuh}/share/vuh'" "$script" ||
    fail 'DATA_DIR does not point at the package'
  ok 'DATA_DIR points into the store'

  # 3. Update checking is compiled out (or in) consistently.
  grep -qF "UPDATE_CHECKS='${lib.boolToString vuh.enableUpdateChecks}'" "$script" ||
    fail 'UPDATE_CHECKS placeholder does not match enableUpdateChecks'
  grep -qF "DAILY_UPDATE_CHECKS='${lib.boolToString vuh.enableUpdateChecks}'" \
    ${vuh}/share/vuh/.installation_info ||
    fail '.installation_info disagrees with enableUpdateChecks'
  ok 'update checking is ${lib.boolToString vuh.enableUpdateChecks} everywhere'

  # 4. The self-installer is gone, along with its predictable temp files.
  for pattern in '/tmp/vuh_update_log.txt' 'auto_update.sh' 'tmp_conf_file="/tmp'; do
    if grep -qF "$pattern" "$script"; then
      fail "leftover in vuh.sh: $pattern"
    fi
  done
  ok 'no self-update code, no predictable temp files'

  # installer.sh and friends have no business being on anyone's PATH.
  for unwanted in installer.sh auto_update.sh vuh.sh vuh-completion.sh; do
    if [ -e "${vuh}/bin/$unwanted" ]; then
      fail "$unwanted was installed into bin/"
    fi
  done
  ok 'only the vuh entry point is in bin/'

  # 5. The shebang was patched to a bash from the store, and that bash can
  #    actually run vuh: `compgen` only exists in a bash built with
  #    programmable completion, and vuh uses it to manage its config variables.
  if ! head -n1 "$script" | grep -qE '^#!/nix/store/[^ ]*/bash$'; then
    fail "shebang was not patched: $(head -n1 "$script")"
  fi
  interpreter=$(head -n1 "$script" | sed 's/^#!//')
  "$interpreter" -c 'compgen -v > /dev/null' ||
    fail "the interpreter ($interpreter) has no compgen; vuh needs one that has"
  ok 'shebang points at a store bash with programmable completion'

  # 6. The wrapper puts vuh's runtime dependencies on PATH.
  for dependency in coreutils git gnugrep gnused findutils; do
    grep -q "/nix/store/[^ :]*-$dependency[^ :]*/bin" "$wrapper" ||
      fail "wrapper does not add $dependency to PATH"
  done
  ok 'wrapper provides coreutils, git, grep, sed and find'

  ${
    if vuh.enableUpdateChecks then
      ''
        grep -q '/nix/store/[^ :]*-curl[^ :]*/bin' "$wrapper" ||
          fail 'update checks are enabled but curl is not on PATH'
        ok 'curl is available for the update check'
      ''
    else
      ''
        if grep -q '/nix/store/[^ :]*-curl[^ :]*/bin' "$wrapper"; then
          fail 'curl is on PATH although update checks are disabled'
        fi
        ok 'curl is not pulled in when update checks are off'
      ''
  }

  # 7. Everything installer.sh would have created exists, in the store.
  [ -f ${vuh}/share/vuh/.installation_info ] || fail 'no .installation_info'
  [ -f "$(echo ${vuh}/share/bash-completion/completions/vuh*)" ] || fail 'no bash completion'
  [ -f ${vuh}/share/zsh/site-functions/_vuh ] || fail 'no zsh completion'
  [ -d ${vuh}/share/vuh/project-config-templates ] || fail 'no project config templates'
  [ -f ${vuh}/share/doc/vuh/README.md ] || fail 'no README'
  ok 'installation layout is complete'

  # 8. The zsh shim's own placeholder was substituted with a path that exists.
  if grep -q '@bashCompletion@' ${vuh}/share/zsh/site-functions/_vuh; then
    fail 'the zsh completion still contains @bashCompletion@'
  fi
  sourced=$(sed -n "s/^source '\(.*\)'$/\1/p" ${vuh}/share/zsh/site-functions/_vuh)
  [ -f "$sourced" ] || fail "the zsh completion sources a file that is not there: $sourced"
  ok 'the zsh completion points at the installed bash completion'

  touch "$out"
''
