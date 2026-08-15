# Overlay adding `vuh` to a nixpkgs instance.
#
#   nixpkgs.overlays = [ (import /path/to/nix-vuh/overlay.nix) ];
#   # or, with flakes:
#   nixpkgs.overlays = [ inputs.nix-vuh.overlays.default ];
final: prev: {
  vuh = final.callPackage ./pkgs/vuh { };
}
