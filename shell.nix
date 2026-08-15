{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShellNoCC {
  packages = [
    (pkgs.callPackage ./pkgs/vuh { })
    pkgs.git
    pkgs.nixfmt-rfc-style
    pkgs.nix-update
    pkgs.shellcheck
  ];
}
