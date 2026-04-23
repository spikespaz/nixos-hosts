{ ... }: {
  image.modules.sealed = { lib, config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-sealed";
    system.image.version = lib.mkDefault "1";

    # UKI injection into ESP (see note in portable-media-base.nix).
    image.repart.partitions."00-brd-esp".contents."/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
      "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

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
    image.repart.partitions."20-brd-system" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "linux-generic";
        Format = "erofs";
        Encrypt = "key-file";
        Minimize = "best";
        Label = "brd-system";
      };
    };
    image.repart.partitions."90-brd-persist" = {
      # Minimum GPT-aligned reservation; systemd-repart extends it
      # into trailing free space on first boot. The "90-" prefix
      # pins this partition last in the GPT (filename sort), so
      # trailing free space is adjacent and grow can claim it.
      repartConfig = {
        Type = "linux-generic";
        SizeMinBytes = "1M";
        Label = "brd-persist";
      };
    };
  };
}
