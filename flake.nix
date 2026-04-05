{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor =
        eachSystem (system: import nixpkgs { localSystem.system = system; });
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

              environment.systemPackages = with pkgs; [ fastfetch ];

              programs.fish.enable = true;
              programs.bash.interactiveShellInit =
                "  if command -v fish &>/dev/null; then\n    exec fish\n  fi\n";

              programs.git.enable = true;

              programs.neovim.enable = true;
              programs.neovim.defaultEditor = true;
            })
          ];
        };
      };

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor;
    };
}

