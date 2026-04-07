{ ... }: {
  imports = [ ./portable-iso-impermanent.nix ];

  system.stateVersion = "25.05";

  # VARIANT_ID in os-release(5). Lowercase, dots/dashes/underscores only.
  # Identifies this image class across all birdboot builds.
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L135-L140
  system.nixos.variant_id = "portable-recovery";

  # NAME and PRETTY_NAME in os-release(5), syslinux/grub boot menu
  # title and entry labels. Default is "NixOS" (capitalized).
  # Does not affect the ISO volume label (that's isoImage.volumeID).
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L128-L133
  system.nixos.distroName = "Birdboot";

  networking.hostName = "birdboot";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
