{
  runCommandLocal,
  bash,
  zsh,
  vuh,
}:

# The completions have to survive being installed, not merely exist.
runCommandLocal "vuh-test-completion"
  {
    nativeBuildInputs = [
      bash
      zsh
    ];
  }
  ''
    set -euo pipefail

    bashCompletion=$(echo ${vuh}/share/bash-completion/completions/vuh*)
    zshSiteFunctions=${vuh}/share/zsh/site-functions

    # --- bash ---------------------------------------------------------------
    # Drive the completion function the way bash would and inspect what it offers.
    complete_with() { # <word being completed> [<words typed before it>...]
      local latest=$1
      shift
      bash --noprofile --norc -c '
        source "$1"
        shift
        COMP_WORDS=(vuh "$@")
        COMP_CWORD=$#
        _vuh_completion
        printf "%s\n" "''${COMPREPLY[@]}"
      ' bash "$bashCompletion" "$@" "$latest"
    }

    expect_suggestion() { # <what> <expected suggestion> <suggestions>
      case "$3" in
        *"$2"*) echo "ok: $1" ;;
        *)
          echo "FAIL: $1: '$2' not among:" >&2
          printf '%s\n' "$3" >&2
          exit 1
          ;;
      esac
    }

    expect_suggestion 'bash completes commands' \
      'update-version' "$(complete_with 'up')"
    expect_suggestion 'bash completes the options of a command' \
      '--check-git-diff' "$(complete_with '--' update-version)"
    expect_suggestion 'bash completes standalone commands' \
      '--configuration' "$(complete_with '--co')"

    # --- zsh ----------------------------------------------------------------
    zsh -n "$zshSiteFunctions/_vuh" || {
      echo 'FAIL: the zsh completion is not valid zsh' >&2
      exit 1
    }
    echo 'ok: zsh completion parses'

    # compinit must pick it up from site-functions, and loading it (which pulls
    # in bashcompinit and sources the bash script) must not error out.
    zsh -f -c '
      set -e
      fpath=("$1" $fpath)
      autoload -Uz compinit
      compinit -u -d "$PWD/zcompdump"
      if (( ! $+_comps[vuh] )); then
        print -u2 "FAIL: compinit did not register a completion for vuh"
        exit 1
      fi
      autoload -Uz bashcompinit && bashcompinit
      source "$2"
      if (( ! $+functions[_vuh_completion] )); then
        print -u2 "FAIL: the bash completion does not load under bashcompinit"
        exit 1
      fi
      # This is the bridge the shipped _vuh relies on: sourcing the bash script
      # ends in `complete -F _vuh_completion vuh`, which bashcompinit has to
      # turn into a zsh completion binding for `vuh`.
      if [[ "$_comps[vuh]" != *_bash_complete*_vuh_completion* ]]; then
        print -u2 "FAIL: bashcompinit did not bind vuh, _comps[vuh] is: $_comps[vuh]"
        exit 1
      fi
      print "ok: zsh picks up the completion"
    ' zsh "$zshSiteFunctions" "$bashCompletion"

    touch "$out"
  ''
