{ lib, pkgs }:

# Option declarations shared by the NixOS and the Home Manager module, so the
# two can never drift apart.
{
  options = {
    enable = lib.mkEnableOption "vuh, a git-aware helper for reading and bumping project versions";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vuh or (pkgs.callPackage ../pkgs/vuh { });
      defaultText = lib.literalExpression "pkgs.vuh";
      description = ''
        The vuh package to use. Defaults to `pkgs.vuh` when this repository's
        overlay is applied, and to a package built from this repository
        otherwise, so the module works with or without the overlay.
      '';
    };

    enableUpdateChecks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Let vuh contact github once a day to see whether a newer release exists,
        and make {command}`vuh --update` report it.

        This is off by default: vuh is installed and updated through Nix, so the
        check can only ever tell you about a version you would still have to
        package yourself, at the cost of a network request per day and a
        timestamp written to {file}`$XDG_STATE_HOME/vuh`. vuh can never replace
        itself in the Nix store regardless of this setting.

        Enabling this rebuilds vuh (it also adds {command}`curl` to its runtime
        closure) and therefore requires {option}`programs.vuh.package` to be
        overridable, which the default is.
      '';
    };

    stateDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/cache/vuh";
      description = ''
        Where vuh keeps the little runtime state it has (currently only the
        timestamp of the last update check). `null` uses the XDG default,
        {file}`$XDG_STATE_HOME/vuh`, falling back to
        {file}`~/.local/state/vuh`.

        This is exported as `VUH_STATE_DIR` and has no effect unless
        {option}`programs.vuh.enableUpdateChecks` is enabled.
      '';
    };
  };

  # `.override` is only reached when the user asks for something other than the
  # package's own default, so a hand-built `package` that takes no arguments
  # keeps working as long as it is left alone.
  packageFor =
    cfg:
    if cfg.enableUpdateChecks then cfg.package.override { enableUpdateChecks = true; } else cfg.package;
}
