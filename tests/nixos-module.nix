{
  lib,
  pkgs,
  callPackage,
  runCommandLocal,
}:

# Evaluate the NixOS module against a stub of the options it touches. Cheap,
# runs on every platform, and catches option typos and `mkIf` mistakes long
# before the (Linux only, VM backed) integration test gets a chance to.
let
  # Built here rather than taken from `passthru.tests`' argument on purpose:
  # `finalAttrs.finalPackage` has no `.override`, and the module's
  # `enableUpdateChecks` option is implemented in terms of it. Same derivation
  # either way.
  vuh = callPackage ../pkgs/vuh { };

  nixosStub =
    { lib, ... }:
    {
      options.environment = {
        systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        sessionVariables = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.oneOf [
              lib.types.str
              lib.types.path
              (lib.types.listOf lib.types.str)
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
        nixosStub
        ../modules/nixos.nix
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

  paths = packages: lib.concatStringsSep " " (map toString packages);
in
runCommandLocal "vuh-test-nixos-module" { } ''
  set -euo pipefail

  fail() { echo "FAIL: $*" >&2; exit 1; }
  ok() { echo "ok: $*"; }

  [ '${toString (builtins.length disabled.environment.systemPackages)}' = '0' ] ||
    fail 'the module installs vuh even when it is disabled'
  ok 'disabled by default'

  [ '${paths enabled.environment.systemPackages}' = '${vuh}' ] ||
    fail 'enabling the module does not put vuh in environment.systemPackages'
  ok 'enable installs exactly the configured package'

  [ '${toString (builtins.length (builtins.attrNames enabled.environment.sessionVariables))}' = '0' ] ||
    fail 'the module sets session variables it was not asked for'
  ok 'no session variables unless asked'

  [ '${withState.environment.sessionVariables.VUH_STATE_DIR or ""}' = '/var/cache/vuh' ] ||
    fail 'stateDirectory is not exported as VUH_STATE_DIR'
  ok 'stateDirectory becomes VUH_STATE_DIR'

  # enableUpdateChecks has to actually rebuild vuh, not merely be recorded.
  [ '${paths withUpdateChecks.environment.systemPackages}' != '${vuh}' ] ||
    fail 'enableUpdateChecks did not override the package'
  [ '${lib.boolToString (lib.head withUpdateChecks.environment.systemPackages).enableUpdateChecks}' = 'true' ] ||
    fail 'the overridden package does not have update checks enabled'
  ok 'enableUpdateChecks overrides the package'

  touch "$out"
''
