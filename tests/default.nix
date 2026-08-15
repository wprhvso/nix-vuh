{
  lib,
  stdenv,
  callPackage,
  vuh,
}:

# Tests that need nothing but a build sandbox (plus a VM for the NixOS one).
# They are wired into `vuh.passthru.tests`, so `nix-build -A vuh.tests` and
# `nix flake check` pick them up.
{
  version = callPackage ./version.nix { inherit vuh; };
  cli = callPackage ./cli.nix { inherit vuh; };
  purity = callPackage ./purity.nix { inherit vuh; };
  completion = callPackage ./completion.nix { inherit vuh; };
  # The module tests build their own (overridable) vuh; see the files.
  nixos-module = callPackage ./nixos-module.nix { };
  home-manager-module = callPackage ./home-manager-module.nix { };
}
// lib.optionalAttrs vuh.enableUpdateChecks {
  # The daily update check is the only thing that writes at runtime, so it only
  # has something to prove in a build that has it enabled.
  state = callPackage ./state.nix { inherit vuh; };
}
// lib.optionalAttrs stdenv.hostPlatform.isLinux {
  # A real NixOS machine with the module enabled. Needs a VM, hence Linux only.
  nixos = callPackage ./nixos.nix { inherit vuh; };
}
