{ ... }: {
  image.modules.immutable = { config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-immutable";

    # UKI injection into ESP (see note in portable-media-base.nix).
    image.repart.partitions."brd-esp".contents."/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
      "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

    # Grow brd-persist to fill available space on first boot.
    systemd.repart.partitions."brd-persist" = {
      Type = "linux-generic";
      Label = "brd-persist";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/disk/by-partlabel/brd-system";
      fsType = "erofs";
    };

    image.repart.partitions."brd-system" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "linux-generic";
        Format = "erofs";
        Minimize = "guess";
        Label = "brd-system";
      };
    };
    image.repart.partitions."brd-persist" = {
      repartConfig = {
        Type = "linux-generic";
        SizeMinBytes = "1G";
        Label = "brd-persist";
      };
    };
  };
}
