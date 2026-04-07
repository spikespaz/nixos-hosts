{ ... }: {
  image.modules.iso-impermanent = { lib, pkgs, modulesPath, config, ... }: {
    imports = [
      # modulesPath is a config-independent argument from lib.evalModules
      # (set in nixos/lib/eval-config.nix). Using pkgs.path here would
      # cause infinite recursion: pkgs depends on config, but imports
      # must resolve before config is available.
      (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ];

    # Reserved for a future feature-set shortcode.
    # When non-empty, appears in both baseName and volumeID.
    isoImage.edition = "";

    # ${distroName}-${edition?}-${label}-${system}.iso
    # mkForce: iso-image.nix hardcodes "nixos" as a bare assignment (priority 100).
    # See: https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/installer/cd-dvd/iso-image.nix#L1033-L1035
    image.baseName = lib.mkForce (lib.concatStringsSep "-" (
      [ (lib.toLower config.system.nixos.distroName) ]
      ++ lib.optional (config.isoImage.edition != "") config.isoImage.edition
      ++ [ config.system.nixos.label pkgs.stdenv.hostPlatform.system ]
    ));

    # ISO 9660 volume label — used at boot by the initrd to locate
    # and mount the CD/USB device (root=LABEL=...). Max 32 characters.
    # ${distroName}-${edition?}-${release}-${arch}
    isoImage.volumeID = lib.concatStringsSep "-" (
      [ (lib.toLower config.system.nixos.distroName) ]
      ++ lib.optional (config.isoImage.edition != "") config.isoImage.edition
      ++ [ config.system.nixos.release pkgs.stdenv.hostPlatform.uname.processor ]
    );

    isoImage.squashfsCompression = "zstd -Xcompression-level 19";

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
