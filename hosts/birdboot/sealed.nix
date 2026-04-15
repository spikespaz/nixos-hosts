{ ... }: {
  image.modules.sealed = { config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-sealed";

    # Grow bb-persist to fill available space on first boot.
    systemd.repart.partitions."bb-persist" = {
      Type = "linux-generic";
      Label = "bb-persist";
    };

    boot.initrd.luks.devices."bb-system" = {
      device = "/dev/disk/by-partlabel/bb-system";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/mapper/bb-system";
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
    # boot.initrd.luks.devices."bb-system" (defined above).
    image.repart.partitions."bb-system" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "linux-generic";
        Format = "erofs";
        Encrypt = "key-file";
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
