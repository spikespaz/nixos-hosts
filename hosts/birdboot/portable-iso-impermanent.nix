{ ... }: {
  image.modules.iso-impermanent = { modulesPath, ... }: {
    imports = [
      # modulesPath is a config-independent argument from lib.evalModules
      # (set in nixos/lib/eval-config.nix). Using pkgs.path here would
      # cause infinite recursion: pkgs depends on config, but imports
      # must resolve before config is available.
      (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ];
    # isoImage.edition is inserted into the ISO filename after "nixos-":
    # nixos-${edition}-${label}-${system}.iso
    # See: https://github.com/NixOS/nixpkgs/blob/b93ddcb44dbf1472f3aac7694922235dc88a8cbd/nixos/modules/installer/cd-dvd/iso-image.nix#L1033-L1035
    # Keep edition short — volumeID has a 32-char ISO 9660 limit
    # and is derived from edition: nixos-${edition}-${release}-${arch}
    isoImage.edition = "birdboot";
    isoImage.squashfsCompression = "zstd -Xcompression-level 19";
  };
}
