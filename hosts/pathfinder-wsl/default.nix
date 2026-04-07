{ pkgs, ... }: {
  system.stateVersion = "25.05";
  networking.hostName = "pathfinder-wsl";
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
  wsl.enable = true;
  wsl.defaultUser = "jacob";
  wsl.interop.register = true;
  wsl.ssh-agent.enable = true;
  wsl.startMenuLaunchers = true;
  wsl.useWindowsDriver = true;

  nix.settings = { experimental-features = [ "nix-command" "flakes" ]; };

  environment.systemPackages = with pkgs; [ fastfetch jq ];

  programs.fish.enable = true;
  programs.bash.interactiveShellInit = ''
    if command -v fish &>/dev/null; then
      exec fish
    fi
  '';

  programs.git.enable = true;

  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
}
