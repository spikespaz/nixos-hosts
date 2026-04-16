{ ... }: {
  image.modules.sealed = { config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-sealed";

    # Grow brd-persist to fill available space on first boot.
    systemd.repart.partitions."brd-persist" = {
      Type = "linux-generic";
      Label = "brd-persist";
    };

    boot.initrd.luks.devices."brd-system" = {
      device = "/dev/disk/by-partlabel/brd-system";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/mapper/brd-system";
      fsType = "erofs";
    };

    # System partition is erofs inside LUKS. systemd-repart creates
    # the LUKS container with a random key-file at build time.
    # The build-time key is NOT stored in the output image.
    #
    # After flashing to USB, the LUKS volume must be re-keyed:
    #   sudo cryptsetup luksFormat /dev/sdX2
    #
    # At boot, the initrd prompts for the LUKS passphrase via
    # boot.initrd.luks.devices."brd-system" (defined above).
    image.repart.partitions."brd-system" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "linux-generic";
        Format = "erofs";
        Encrypt = "key-file";
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
