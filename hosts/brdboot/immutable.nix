{ ... }: {
  image.modules.immutable = { config, lib, ... }: {
    imports = [ ./portable-media-base.nix ];

    system.image.id = "${config.system.nixos.distroId}-immutable";
    # Required for the verityStore module — it reads previousAttrs.pname
    # on the intermediate image derivation, and repart-image.nix only sets
    # pname when version is non-null (falls back to bare `name` otherwise).
    system.image.version = lib.mkDefault "1";

    # systemd-based initrd is required for dm-verity activation — the
    # verityStore module sets boot.initrd.systemd.dmVerity.enable which
    # only takes effect when the initrd uses systemd.
    boot.initrd.systemd.enable = true;

    # Fail loudly on any dm-verity corruption instead of silently with
    # per-read EIO. Without this, a flashed drive with bad blocks (or
    # an image tampered with offline) still boots as long as the bad
    # blocks aren't on the critical boot path — the kernel returns
    # EIO only for reads that touch corrupt blocks, and a dmesg scan
    # is the only way to notice. A recovery image's whole value is
    # integrity; make corruption an immediate visible kernel panic.
    #
    # OPTIONS syntax is comma-separated and ends up on the UKI
    # cmdline as `systemd.verity_usr_options=...`; systemd-initrd's
    # veritysetup-generator passes the value through to dm-verity's
    # device table. See systemd-veritysetup-generator(8) and
    # https://docs.kernel.org/admin-guide/device-mapper/verity.html
    boot.kernelParams = [
      "systemd.verity_usr_options=panic-on-corruption"
    ];

    # UKI injection is handled by the verityStore module's finalImage override.
    # The module bakes the verity root hash into the UKI cmdline.
    #
    # The module uses GPT partition types from the Discoverable Partition
    # Specification (DPS): partitions are identified by well-known GUIDs,
    # so systemd-initrd auto-discovers and mounts them without an fstab.
    # brd-system gets the "usr" type (mounted at /usr) and brd-system-verity
    # gets the paired "usr-verity" type, which triggers dm-verity activation
    # automatically. See:
    # https://uapi-group.org/specifications/specs/discoverable_partitions_specification/
    image.repart.verityStore = {
      enable = true;
      partitionIds = {
        esp = "brd-esp";
        store-verity = "brd-system-verity";
        store = "brd-system";
      };
    };

    # Keep brd-* GPT label convention — module defaults to "store"/"store-verity".
    # Minimize = "best" shrinks each partition to just fit its contents; without
    # this, the verity data/hash partitions get a near-empty default size and
    # the build fails with "contents don't fit in the partition".
    image.repart.partitions = {
      "brd-system".repartConfig = {
        Label = lib.mkImageMediaOverride "brd-system";
        Minimize = "best";
      };
      "brd-system-verity".repartConfig = {
        Label = lib.mkImageMediaOverride "brd-system-verity";
        Minimize = "best";
      };
      "brd-persist" = {
        # Minimum GPT-aligned reservation; systemd-repart grows it on
        # first boot.
        repartConfig = {
          Type = "linux-generic";
          SizeMinBytes = "1M";
          Label = "brd-persist";
        };
      };
    };

    # Grow brd-persist to fill available space on first boot.
    systemd.repart.partitions."brd-persist" = {
      Type = "linux-generic";
      Label = "brd-persist";
    };

    fileSystems = {
      "/" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      # /usr is auto-mounted by systemd via the DPS "usr" type (see
      # verityStore comment above). The nix store lives at /usr/nix/store;
      # bind it to the canonical /nix/store location.
      "/nix/store" = {
        device = "/usr/nix/store";
        options = [ "bind" ];
      };
    };
  };
}
