{ ... }: {
  imports = [
    ./portable-iso-impermanent.nix
  ];

  system.stateVersion = "25.05";
  networking.hostName = "birdboot-portable";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
