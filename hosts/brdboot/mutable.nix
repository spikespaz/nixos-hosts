{ ... }: {
  image.modules.mutable = { lib, config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-mutable";
    system.image.version = lib.mkDefault "1";

    # UKI injection into ESP (see note in portable-media-base.nix).
    image.repart.partitions."brd-esp".contents."/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
      "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

    # Grow brd-root to fill available space on first boot.
    systemd.repart.partitions."brd-root" = {
      Type = "root";
      Label = "brd-root";
    };

    fileSystems."/" = {
      device = "/dev/disk/by-partlabel/brd-root";
      fsType = "ext4";
      autoResize = true;
    };

    image.repart.partitions."brd-root" = {
      storePaths = [ config.system.build.toplevel ];
      contents = {
        "/nix/var/nix/profiles/system".source = config.system.build.toplevel;
      };
      repartConfig = {
        Type = "root";
        Format = "ext4";
        # ext4 is read-write and repart rejects Minimize=best on it
        # ("can only be used with read-only filesystems or Verity=hash").
        # "guess" stays — brd-root grows to fill the disk at first boot
        # anyway, so the build-time padding is recovered.
        Minimize = "guess";
        Label = "brd-root";
      };
    };
  };
}
