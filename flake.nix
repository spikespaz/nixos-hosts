{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }: {
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
          })
        ];
      };
    };
  };
}

