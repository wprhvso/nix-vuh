{
  config,
  lib,
  pkgs,
  ...
}:

let
  common = import ./common.nix { inherit lib pkgs; };
  cfg = config.programs.vuh;
  package = common.packageFor cfg;
in
{
  options.programs.vuh = common.options;

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];

    # Bash and zsh completions are installed into the usual
    # `share/bash-completion/completions` and `share/zsh/site-functions`
    # directories, so `programs.bash.completion.enable` (on by default) and
    # `programs.zsh.enableCompletion` pick them up without further help.
    # Note that NixOS only links `share/zsh` into the system profile when
    # `programs.zsh.enable` is set; that is the zsh module's call, not ours.

    environment.sessionVariables = lib.optionalAttrs (cfg.stateDirectory != null) {
      VUH_STATE_DIR = cfg.stateDirectory;
    };
  };
}
