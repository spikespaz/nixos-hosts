{ ... }: {
  image.modules.immutable = { config, lib, pkgs, ... }:
    let
      # Bare filename (not a path) — shared below as ukify's --output
      # basename and as the ESP source path's basename. Must match
      # verityStore's finalImage injection, which uses the same form.
      ukiFile = config.system.boot.loader.ukiFile;

      # Sizing UKI for the ESP: verityStore injects the real (verity-
      # hashed) UKI into finalImage, so at intermediate-image time repart
      # sees no UKI content and would size the ESP to a few hundred KiB —
      # too small for the real UKI (tens of MiB) to fit later.
      #
      # Fix: seed a placeholder UKI at the exact path verityStore uses,
      # with a cmdline byte-matched to the real one — same `init=... <kernel
      # params>` format plus `usrhash=` with 64 zero hex digits in place of
      # the real SHA-256. Identical cmdline byte length → identical PE
      # .cmdline section alignment → identical UKI file size → ESP sized
      # exactly. At finalImage time verityStore's lib.recursiveUpdate
      # replaces the placeholder .source with the real UKI.
      placeholderHash = lib.concatStrings (lib.genList (_: "0") 64);

      # Byte-match upstream's cmdline construction — verityStore builds the
      # same string and appends the real hash as `${cmdline} usrhash=$usrhash`:
      # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/image/repart-verity-store.nix#L149-L172
      sizingCmdline = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} usrhash=${placeholderHash}";

      # Mirrors verityStore's own runCommand + ukify build invocation at the
      # link above — same flags (--config, --cmdline, --output), same
      # nativeBuildInputs (systemdUkify; jq is only needed for the real
      # usrhash extraction). Can't just reference config.system.build.uki:
      # verityStore overrides it to depend on the intermediate image (for
      # the real usrhash), and the intermediate image's size depends on the
      # ESP → cycle.
      sizingUki = pkgs.runCommand "brdboot-immutable-sizing-uki" {
        nativeBuildInputs = [ pkgs.buildPackages.systemdUkify ];
      } ''
        mkdir -p $out
        ukify build \
          --config=${config.boot.uki.configFile} \
          --cmdline="${sizingCmdline}" \
          --output="$out/${ukiFile}"
      '';
    in
    {
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

    # Seed the ESP with a placeholder UKI at the exact path verityStore
    # will later use for the real UKI, so Minimize="guess" from
    # portable-media-base sizes the partition correctly at intermediate
    # time. See the sizingUki let-binding above for the full rationale.
    image.repart.partitions."brd-esp".contents = {
      "${config.image.repart.verityStore.ukiPath}".source =
        "${sizingUki}/${ukiFile}";
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
        # Minimum GPT-aligned reservation; systemd-repart extends it
        # into trailing free space on first boot.
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
