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
      mkBrdboot = { pkgs, modules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit pkgs;
          modules = modules ++ [
            ./hosts/brdboot
            {
              system.image.version = lib.mkIf setImageVersion
                (builtins.substring 0 7 (self.rev or self.dirtyRev or "unknown"));
            }
          ];
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

        brdboot = mkBrdboot { pkgs = pkgsFor."x86_64-linux"; };

        brdboot-aarch64 = mkBrdboot { pkgs = pkgsFor."aarch64-linux"; };
      };

      packages = lib.mapAttrs (buildSystem: pkgs:
        let
          brdbootFor = {
            "x86_64-linux" = self.nixosConfigurations.brdboot;
            "aarch64-linux" =
              self.nixosConfigurations.brdboot-aarch64;
          };
          native = lib.optionalAttrs (brdbootFor ? ${buildSystem}) {
            brdboot-images =
              brdbootFor.${buildSystem}.config.system.build.images;
          };
          cross = lib.concatMapAttrs (hostSystem: config:
            lib.optionalAttrs (hostSystem != buildSystem) {
              "brdboot-images-${hostSystem}" = (mkBrdboot {
                pkgs = pkgsCrossFor buildSystem hostSystem;
              }).config.system.build.images;
            }) brdbootFor;
          localPackages = {
            brdboot-pam-credential =
              pkgs.callPackage ./packages/brdboot-pam-credential { };
          };
        in native // cross // localPackages) pkgsFor;

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor;
    };
}
