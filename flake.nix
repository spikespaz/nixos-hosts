{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }: let
    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    pkgsFor = eachSystem (system:
      import nixpkgs {
        localSystem.system = system;
      }
    );
  in {
    nixosConfigurations = {
      pathfinder-wsl = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          ({ pkgs, ... }: {
            system.stateVersion = "25.05";
            networking.hostName = "pathfinder-wsl";
            wsl.enable = true;
	    wsl.defaultUser = "jacob";
	    wsl.interop.register = true;
	    wsl.ssh-agent.enable = true;
	    wsl.startMenuLaunchers = true;
	    wsl.useWindowsDriver = true;
            
	    nix.settings = {
              experimental-features = ["nix-command" "flakes"];
	    };

	    environment.systemPackages = with pkgs; [
              neovim
	      git
	      fastfetch
	    ];

	    programs.fish.enable = true;
	    programs.bash.interactiveShellInit = ''
	      if command -v fish &>/dev/null; then
	        exec fish
	      fi
	    '';
          })
        ];
      };
    };

    formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor; 
  };
}

