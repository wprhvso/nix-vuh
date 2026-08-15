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
    home.packages = [ package ];

    # No shell snippets needed: the completions land in the profile's
    # `share/bash-completion/completions` and `share/zsh/site-functions`, which
    # `programs.bash.enableCompletion` and `programs.zsh.enableCompletion`
    # already search.

    home.sessionVariables = lib.optionalAttrs (cfg.stateDirectory != null) {
      VUH_STATE_DIR = cfg.stateDirectory;
    };
  };
}
