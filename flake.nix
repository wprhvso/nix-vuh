{
  description = "vuh (version-update-helper) packaged for Nix, with NixOS and Home Manager modules";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      nixFiles = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      packages = forAllSystems (pkgs: rec {
        vuh = pkgs.callPackage ./pkgs/vuh { };
        default = vuh;
      });

      nixosModules = rec {
        vuh = ./modules/nixos.nix;
        default = vuh;
      };

      # `homeManagerModules` is the spelling home-manager's own documentation
      # used for years; `homeModules` is the one Nix knows about. Both work.
      homeManagerModules = rec {
        vuh = ./modules/home-manager.nix;
        default = vuh;
      };
      homeModules = self.homeManagerModules;

      checks = forAllSystems (
        pkgs:
        let
          vuh = self.packages.${pkgs.stdenv.hostPlatform.system}.vuh;
          vuhWithUpdateChecks = vuh.override { enableUpdateChecks = true; };
        in
        {
          inherit vuh;

          # The optional feature has its own code path, so build it and check
          # that the build time switch really reached every place it has to.
          vuh-with-update-checks = vuhWithUpdateChecks;
          vuh-with-update-checks-purity = vuhWithUpdateChecks.tests.purity;
          vuh-with-update-checks-state = vuhWithUpdateChecks.tests.state;

          formatting =
            pkgs.runCommandLocal "check-nixfmt" { nativeBuildInputs = [ pkgs.nixfmt-rfc-style ]; }
              ''
                find ${nixFiles} -name '*.nix' -print0 | xargs -0 nixfmt --check
                touch "$out"
              '';
        }
        # `callPackage` decorates the test set with `override`, which is not a
        # derivation and would make `nix flake check` unhappy.
        // lib.mapAttrs' (name: lib.nameValuePair "vuh-${name}") (
          lib.filterAttrs (_: lib.isDerivation) vuh.tests
        )
      );

      devShells = forAllSystems (pkgs: {
        default = import ./shell.nix { inherit pkgs; };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);

      apps = forAllSystems (pkgs: rec {
        vuh = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.vuh;
          meta.description = "Read, compare and bump your project's semantic version";
        };
        default = vuh;
      });
    };
}
