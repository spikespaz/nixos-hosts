{ ... }: {
  image.modules.ephemeral = { lib, pkgs, modulesPath, config, ... }: {
    imports = [
      # modulesPath is a config-independent argument from lib.evalModules
      # (set in nixos/lib/eval-config.nix). Using pkgs.path here would
      # cause infinite recursion: pkgs depends on config, but imports
      # must resolve before config is available.
      (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ];

    # Reserved for a future feature-set shortcode.
    # When non-empty, appears in both baseName and volumeID.
    system.image.id = "${config.system.nixos.distroId}-ephemeral";
    system.image.version = lib.mkDefault "1";
    isoImage.edition = "";

    # ${image.id}-${label}-${system}-${version}.iso
    # Overrides iso-image.nix's hardcoded "nixos-..." baseName
    # (https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/installer/cd-dvd/iso-image.nix#L1033-L1035).
    # Use lib.mkForce to override further. Dash separator matches
    # repart-image.nix, keeping filenames consistent across variants.
    image.baseName = lib.mkImageMediaOverride (lib.concatStringsSep "-" (
      [
        config.system.image.id
        config.system.nixos.label
        pkgs.stdenv.hostPlatform.system
      ] ++ lib.optional (config.system.image.version != null)
        config.system.image.version
    ));

    # ISO 9660 volume label — used at boot by the initrd to locate
    # and mount the CD/USB device (root=LABEL=...). Max 32 characters.
    # ${image.id}-${release}-${arch} (max 32 chars)
    isoImage.volumeID = lib.concatStringsSep "-" [
      config.system.image.id
      config.system.nixos.release
      pkgs.stdenv.hostPlatform.uname.processor
    ];

    isoImage.squashfsCompression = "zstd -Xcompression-level 19";

    # Boot menu entry: "${prependToMenuLabel}${distroName} ${label}${appendToMenuLabel}"
    # isoImage.prependToMenuLabel = "";
    isoImage.appendToMenuLabel = " [ISO]";

    # These three options are independent — each adds a different boot
    # mechanism to the ISO via xorriso flags. All three are needed for
    # a USB stick that boots on any firmware.
    #
    # makeBiosBootable: adds El-Torito boot record for CD boot on BIOS.
    #   Defaults to true when both build and host are x86 (isx86 covers
    #   both i686 and x86_64). False on aarch64 because BIOS doesn't
    #   exist on ARM — only UEFI.
    #   Already true for our x86_64 build; not set explicitly.
    #   https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/installer/cd-dvd/iso-image.nix#L634-L650
    #
    # makeUsbBootable: embeds an MBR partition table via isohybrid
    #   (syslinux isohdpfx.bin) so the ISO is recognized as a bootable
    #   disk when dd'd to USB. Without it, USB firmware sees no partition
    #   table. Requires makeBiosBootable (the MBR chains to syslinux).
    #   https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/lib/make-iso9660-image.sh#L45-L52
    isoImage.makeUsbBootable = true;
    #
    # makeEfiBootable: adds a GPT with an EFI system partition entry
    #   (-isohybrid-gpt-basdat). Enables UEFI boot from both CD and USB.
    #   Independent of the MBR — UEFI firmware reads GPT, not MBR.
    #   https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/lib/make-iso9660-image.sh#L54-L57
    isoImage.makeEfiBootable = true;
  };
}
