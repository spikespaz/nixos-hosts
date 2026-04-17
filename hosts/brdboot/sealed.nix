{ ... }: {
  image.modules.sealed = { lib, config, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-sealed";
    system.image.version = lib.mkDefault "1";

    # UKI injection into ESP (see note in portable-media-base.nix).
    image.repart.partitions."brd-esp".contents."/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
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
    # Minimum GPT-aligned reservation; systemd-repart grows it on first
    # boot.
    image.repart.partitions."brd-persist" = {
      repartConfig = {
        Type = "linux-generic";
        SizeMinBytes = "1M";
        Label = "brd-persist";
      };
    };

    # Small plaintext partition holding per-user <user>.keystore LUKS
    # blobs. The partition is plaintext at the block level, but each
    # keystore file is itself a LUKS2 container keyed by the user's
    # password — so the only leak is the list of enrolled usernames
    # and their count. Deployment key material stays behind each
    # keystore's LUKS envelope.
    #
    # Pre-formatted as ext4 at build time so repart accepts the
    # Minimize="guess" directive (repart requires Format= to be set
    # before it will honor Minimize=) and so provisioning can drop
    # <user>.keystore files straight into the existing filesystem
    # without needing to mkfs first. 16 MiB floor covers ext4 metadata
    # plus a dozen-ish keystores; guess packs tighter when build-time
    # contents are supplied (see #38 for a later switch to erofs).
    #
    # No DPS type fits, so we use linux-generic and look up by
    # partlabel at runtime rather than relying on auto-discovery.
    image.repart.partitions."brd-keystores" = {
      repartConfig = {
        Type = "linux-generic";
        Format = "ext4";
        SizeMinBytes = "16M";
        Minimize = "guess";
        Label = "brd-keystores";
      };
    };
  };
}
