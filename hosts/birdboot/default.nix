{ ... }: {
  imports = [ ./portable-iso-impermanent.nix ];

  system.stateVersion = "25.05";
  system.nixos.distroName = "birdboot-portable";
  networking.hostName = "birdboot-portable";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
