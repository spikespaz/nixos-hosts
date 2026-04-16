{ ... }: {
  image.modules.mutable = { config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-mutable";

    # Grow bb-root to fill available space on first boot.
    systemd.repart.partitions."bb-root" = {
      Type = "root";
      Label = "bb-root";
    };

    fileSystems."/" = {
      device = "/dev/disk/by-partlabel/bb-root";
      fsType = "ext4";
      autoResize = true;
    };

    image.repart.partitions."bb-root" = {
      storePaths = [ config.system.build.toplevel ];
      contents = {
        "/nix/var/nix/profiles/system".source = config.system.build.toplevel;
      };
      repartConfig = {
        Type = "root";
        Format = "ext4";
        Minimize = "guess";
        Label = "bb-root";
      };
    };
  };
}
