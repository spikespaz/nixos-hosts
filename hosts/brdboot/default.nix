{ ... }: {
  imports = [
    ./ephemeral.nix
    ./mutable.nix
    ./immutable.nix
    ./sealed.nix
  ];

  system.stateVersion = "25.05";

  # ID in os-release(5), lsb-release DISTRIB_ID, DEFAULT_HOSTNAME.
  # Changing from "nixos" automatically sets ID_LIKE = "nixos" so
  # tooling that checks for NixOS compatibility still works.
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L121-L126
  system.nixos.distroId = "brdboot";

  # NAME and PRETTY_NAME in os-release(5), syslinux/grub boot menu
  # title and entry labels. Default is "NixOS" (capitalized).
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L128-L133
  system.nixos.distroName = "Brdboot";

  # VARIANT_ID and VARIANT in os-release(5).
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L135-L147
  system.nixos.variant_id = "portable-recovery";
  system.nixos.variantName = "Brdboot: Portable Recovery";

  networking.hostName = "brdboot";

  # Load initrd modules for all common storage controllers (AHCI, NVMe,
  # USB, SCSI, SD, virtio, VMware, Hyper-V) and bundle redistributable
  # firmware (linux-firmware, WiFi, audio). Without this the ISO can't
  # find its own USB stick on most hardware — the initrd only has
  # squashfs, iso9660, uas, overlay, loop by default.
  # See: https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/hardware/all-hardware.nix
  hardware.enableAllHardware = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Stopgap so HW-test logins work before homed-based account creation
  # lands. Flashed images accept `root` / `password` at the tty1 prompt,
  # which is enough to run `dmesg | grep verity`, `findmnt /usr`, and
  # confirm the verity activation + tamper-detection paths.
  #
  # To be cleaned up once the homed-enablement PR (carved from #36)
  # introduces proper per-user encrypted homes and a first-boot prompt.
  users.users.root.initialPassword = "password";
}
