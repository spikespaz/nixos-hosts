{ ... }: {
  image.modules.immutable = { config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-immutable";

    # Grow bb-persist to fill available space on first boot.
    systemd.repart.partitions."bb-persist" = {
      Type = "linux-generic";
      Label = "bb-persist";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/disk/by-partlabel/bb-system";
      fsType = "erofs";
    };

    image.repart.partitions."bb-system" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "linux-generic";
        Format = "erofs";
        Minimize = "guess";
        Label = "bb-system";
      };
    };
    image.repart.partitions."bb-persist" = {
      repartConfig = {
        Type = "linux-generic";
        SizeMinBytes = "1G";
        Label = "bb-persist";
      };
    };
  };
}
