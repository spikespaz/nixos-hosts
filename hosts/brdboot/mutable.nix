{ ... }: {
  image.modules.mutable = { lib, config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-mutable";
    system.image.version = lib.mkDefault "1";

    # UKI injection into ESP (see note in portable-media-base.nix).
    image.repart.partitions."00-brd-esp".contents."/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
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

    image.repart.partitions."20-brd-root" = {
      storePaths = [ config.system.build.toplevel ];
      contents = {
        "/nix/var/nix/profiles/system".source = config.system.build.toplevel;
      };
      repartConfig = {
        Type = "root";
        Format = "ext4";
        Minimize = "guess";
        Label = "brd-root";
      };
    };
  };
}
