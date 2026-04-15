{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor =
        eachSystem (system: import nixpkgs { localSystem.system = system; });
      pkgsCrossFor = localSystem: crossSystem:
        import nixpkgs {
          localSystem.system = localSystem;
          crossSystem.system = crossSystem;
        };
      # Caller modules are ordered before host defaults so callers can
      # use mkOrder and mkOverride to override without fighting evaluation order.
      setImageVersion = false;
      mkBirdboot = { pkgs, modules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit pkgs;
          modules = modules ++ [
            ./hosts/birdboot
          ] ++ lib.optional setImageVersion {
            system.image.version =
              builtins.substring 0 7 (self.rev or self.dirtyRev or "unknown");
          };
        };
    in {
      nixosConfigurations = {
        pathfinder-wsl = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/pathfinder-wsl
          ];
        };

        birdboot-portable = mkBirdboot { pkgs = pkgsFor."x86_64-linux"; };

        birdboot-portable-aarch64 = mkBirdboot { pkgs = pkgsFor."aarch64-linux"; };
      };

      packages = lib.mapAttrs (buildSystem: _:
        let
          birdbootFor = {
            "x86_64-linux" = self.nixosConfigurations.birdboot-portable;
            "aarch64-linux" =
              self.nixosConfigurations.birdboot-portable-aarch64;
          };
          native = lib.optionalAttrs (birdbootFor ? ${buildSystem}) {
            birdboot-images =
              birdbootFor.${buildSystem}.config.system.build.images;
          };
          cross = lib.concatMapAttrs (hostSystem: config:
            lib.optionalAttrs (hostSystem != buildSystem) {
              "birdboot-images-${hostSystem}" = (mkBirdboot {
                pkgs = pkgsCrossFor buildSystem hostSystem;
              }).config.system.build.images;
            }) birdbootFor;
        in native // cross) pkgsFor;

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor;
    };
}
