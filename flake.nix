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
      mkBirdboot = { pkgs, modules ? [ ] }: nixpkgs.lib.nixosSystem {
        inherit pkgs;
        modules = modules ++ [ ./hosts/birdboot ];
      };
    in {
      nixosConfigurations = {
        pathfinder-wsl = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-wsl.nixosModules.default
            ({ pkgs, config, ... }: {
              system.stateVersion = "25.05";
              networking.hostName = "pathfinder-wsl";
              boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
              wsl.enable = true;
              wsl.defaultUser = "jacob";
              wsl.interop.register = true;
              wsl.ssh-agent.enable = true;
              wsl.startMenuLaunchers = true;
              wsl.useWindowsDriver = true;

              nix.settings = {
                experimental-features = [ "nix-command" "flakes" ];
              };

              environment.systemPackages = with pkgs; [ fastfetch jq ];

              programs.fish.enable = true;
              programs.bash.interactiveShellInit =
                "  if command -v fish &>/dev/null; then\n    exec fish\n  fi\n";

              programs.git.enable = true;

              programs.neovim.enable = true;
              programs.neovim.defaultEditor = true;
            })
          ];
        };

        birdboot-portable = mkBirdboot {
          pkgs = pkgsFor."x86_64-linux";
        };
      };

      # TODO: hostSystem should be parameterized — aarch64-linux may
      # also be a host system in the future. Consider lifting to a
      # per-host config attrset that maps hostSystem → nixosConfiguration.
      packages = lib.mapAttrs (buildSystem: pkgs:
        let
          hostSystem = "x86_64-linux";
          isCross = buildSystem != hostSystem;
          name = "birdboot-images"
            + lib.optionalString isCross "-${hostSystem}";
          images = if isCross then
            let pkgs = pkgsCrossFor buildSystem hostSystem;
            in (mkBirdboot { inherit pkgs; }).config.system.build.images
          else
            self.nixosConfigurations.birdboot-portable.config.system.build.images;
        in { ${name} = images; }) pkgsFor;

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor;
    };
}
