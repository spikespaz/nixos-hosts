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

  # USB/IP passthrough so arbitrary USB devices bound on the Windows
  # side (via usbipd-win) appear as real /dev/sdX, /dev/ttyUSB*, etc.
  # inside WSL rather than only the whole-disk bare-mount form.
  #
  # Windows-side setup: `winget install dorssel.usbipd-win`. Per-device
  # attach from an elevated PowerShell:
  #   usbipd list
  #   usbipd bind   --busid <N-N>
  #   usbipd attach --wsl --busid <N-N>
  #
  # snippetIpAddress defaults to reading the eth0 gateway, which is
  # correct for NAT networking; override if using networkingMode =
  # mirrored or wsl-vpnkit.
  wsl.usbip.enable = true;

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
