{
  lib,
  pkgs,
  callPackage,
  runCommandLocal,
}:

# Evaluate the Home Manager module against a stub of the few Home Manager
# options it touches. This keeps the module honest (option types, `mkIf`
# handling, the override path) without dragging home-manager in as an input.
let
  # Built here rather than taken from `passthru.tests`' argument on purpose:
  # `finalAttrs.finalPackage` has no `.override`, and the module's
  # `enableUpdateChecks` option is implemented in terms of it. Same derivation
  # either way.
  vuh = callPackage ../pkgs/vuh { };

  homeManagerStub =
    { lib, ... }:
    {
      options.home = {
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        sessionVariables = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.oneOf [
              lib.types.str
              lib.types.int
              lib.types.path
            ]
          );
          default = { };
        };
      };
    };

  evalWith =
    settings:
    (lib.evalModules {
      modules = [
        homeManagerStub
        ../modules/home-manager.nix
        { _module.args.pkgs = pkgs; }
        { programs.vuh = settings; }
      ];
    }).config;

  disabled = evalWith { enable = false; };
  enabled = evalWith {
    enable = true;
    package = vuh;
  };
  withState = evalWith {
    enable = true;
    package = vuh;
    stateDirectory = "/var/cache/vuh";
  };
  withUpdateChecks = evalWith {
    enable = true;
    package = vuh;
    enableUpdateChecks = true;
  };

  paths = packages: map toString packages;
in
runCommandLocal "vuh-test-home-manager-module" { } ''
  set -euo pipefail

  fail() { echo "FAIL: $*" >&2; exit 1; }
  ok() { echo "ok: $*"; }

  [ '${toString (builtins.length disabled.home.packages)}' = '0' ] ||
    fail 'the module installs vuh even when it is disabled'
  ok 'disabled by default'

  [ '${lib.concatStringsSep " " (paths enabled.home.packages)}' = '${vuh}' ] ||
    fail 'enabling the module does not put vuh in home.packages'
  ok 'enable installs exactly the configured package'

  [ '${toString (builtins.length (builtins.attrNames enabled.home.sessionVariables))}' = '0' ] ||
    fail 'the module sets session variables it was not asked for'
  ok 'no session variables unless asked'

  [ '${withState.home.sessionVariables.VUH_STATE_DIR or ""}' = '/var/cache/vuh' ] ||
    fail 'stateDirectory is not exported as VUH_STATE_DIR'
  ok 'stateDirectory becomes VUH_STATE_DIR'

  # enableUpdateChecks has to actually rebuild vuh, not just be recorded.
  [ '${lib.concatStringsSep " " (paths withUpdateChecks.home.packages)}' != '${vuh}' ] ||
    fail 'enableUpdateChecks did not override the package'
  [ '${lib.boolToString (lib.head withUpdateChecks.home.packages).enableUpdateChecks}' = 'true' ] ||
    fail 'the overridden package does not have update checks enabled'
  ok 'enableUpdateChecks overrides the package'

  touch "$out"
''
