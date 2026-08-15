# Entry point for people who do not use flakes:
#
#   nix-build                     # builds vuh
#   nix-build -A tests            # builds every test
#   nix-env -f . -i vuh           # installs it into your profile
#
# `pkgs` defaults to <nixpkgs> from your channels; pass your own if you pin
# nixpkgs some other way (npins, niv, a fetchTarball, ...):
#
#   nix-build --arg pkgs 'import (fetchTarball "...") {}'
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.callPackage ./pkgs/vuh { }
