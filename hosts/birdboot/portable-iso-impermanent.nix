{ ... }: {
  image.modules.iso-impermanent = { pkgs, ... }: {
    imports = [
      (pkgs.path + "/nixos/modules/installer/cd-dvd/iso-image.nix")
    ];
    isoImage.squashfsCompression = "zstd -Xcompression-level 19";
  };
}
