{ testers, vuh }:

# A real NixOS machine with `programs.vuh.enable = true`, driven the way a user
# would drive it. Needs a VM, so this one is Linux only.
testers.runNixOSTest {
  name = "vuh";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../modules/nixos.nix ];

      programs.vuh = {
        enable = true;
        package = vuh;
      };

      users.users.alice = {
        isNormalUser = true;
      };

      # NixOS only links `share/zsh` into the system profile when zsh is
      # enabled, so a machine without zsh cannot have the zsh completion no
      # matter how the package installs it. Enable it and check the real thing.
      programs.zsh.enable = true;

      # The scripts the test drives, kept out of the test script itself so they
      # do not have to survive three levels of quoting.
      environment.systemPackages = [
        pkgs.git

        (pkgs.writeShellScriptBin "vuh-bump-a-version" ''
          set -eu
          cd "$HOME"
          git config --global user.name alice
          git config --global user.email alice@example.invalid
          git config --global init.defaultBranch main

          git init -q --bare origin.git
          git clone -q origin.git project
          cd project

          cat > .vuh <<'CONF'
          MAIN_BRANCH_NAME='main'
          VERSION_FILE='version.sh'
          TEXT_BEFORE_VERSION_CODE="VERSION='"
          TEXT_AFTER_VERSION_CODE="'"
          CONF

          echo "VERSION='1.0.0'" > version.sh
          git add .
          git commit -qm 'initial'
          git push -q -u origin main

          git checkout -q -b feature
          echo 'a change' > code.txt
          git add .
          git commit -qm 'a change'

          test "$(vuh lv -q)" = 1.0.0
          test "$(vuh mv -q)" = 1.0.0
          test "$(vuh sv -q)" = 1.0.1
          test "$(vuh uv -q)" = 1.0.1
          grep -qxF "VERSION='1.0.1'" version.sh
          echo 'version bumped'
        '')

        # Explicitly bashInteractive: `writeShellScriptBin` uses the
        # non-interactive bash, which has no `complete`/`compgen` at all.
        (pkgs.writeScriptBin "vuh-complete" ''
          #!${pkgs.bashInteractive}/bin/bash
          set -eu
          source "$(echo /run/current-system/sw/share/bash-completion/completions/vuh*)"
          COMP_WORDS=(vuh "$@")
          COMP_CWORD=$#
          _vuh_completion
          printf '%s\n' "''${COMPREPLY[@]}"
        '')

        (pkgs.writeScriptBin "vuh-complete-zsh" ''
          #!${pkgs.zsh}/bin/zsh -f
          set -e
          # The directory `programs.zsh.enableCompletion` puts on fpath.
          fpath=(/run/current-system/sw/share/zsh/site-functions $fpath)
          autoload -Uz compinit
          compinit -u -d "$(mktemp -d)/zcompdump"
          if (( ! $+_comps[vuh] )); then
            print -u2 'compinit did not register a completion for vuh'
            exit 1
          fi
          print 'zsh knows about vuh'
        '')
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("vuh is on PATH and reports its version"):
        machine.succeed("vuh --version | grep -F '${vuh.version}'")
        machine.succeed("vuh --help | grep -F 'Usage: vuh'")

    with subtest("the installation info describes this NixOS installation"):
        machine.succeed("vuh --configuration | grep -F \"INSTALLATION_DIR='${vuh}/bin'\"")
        machine.succeed("vuh --configuration | grep -F \"DAILY_UPDATE_CHECKS='false'\"")

    with subtest("vuh refuses to update itself"):
        machine.fail("vuh --update")

    with subtest("shell completions are installed system wide"):
        machine.succeed("ls /run/current-system/sw/share/bash-completion/completions/vuh*")
        machine.succeed("test -f /run/current-system/sw/share/zsh/site-functions/_vuh")
        machine.succeed("vuh-complete up | grep -F update-version")
        machine.succeed("vuh-complete-zsh | grep -F 'zsh knows about vuh'")

    with subtest("an unprivileged user can bump a version end to end"):
        machine.succeed("su alice -l -c vuh-bump-a-version | grep -F 'version bumped'")

    with subtest("nothing was written into the store"):
        machine.succeed("test ! -e ${vuh}/share/vuh/latest_update_check")
  '';
}
