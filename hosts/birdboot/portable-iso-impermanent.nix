{ ... }: {
  image.modules.iso-impermanent = { modulesPath, ... }: {
    imports = [
      # modulesPath is a config-independent argument from lib.evalModules
      # (set in nixos/lib/eval-config.nix). Using pkgs.path here would
      # cause infinite recursion: pkgs depends on config, but imports
      # must resolve before config is available.
      (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ];
    isoImage.squashfsCompression = "zstd -Xcompression-level 19";
  };
}
