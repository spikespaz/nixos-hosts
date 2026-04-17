{ ... }: {
  image.modules.immutable = { config, lib, pkgs, ... }:
    let
      ukiFile = config.system.boot.loader.ukiFile;

      # The verityStore module defers ESP population to finalImage and
      # injects the real (verity-hashed) UKI there via finalPartitions.
      # At intermediate-image time repart therefore sees only the
      # bootloader + loader.conf as ESP contents and would size the
      # partition to a few hundred KiB — finalImage would then fail to
      # fit the ~100 MiB UKI into the pre-sized partition.
      #
      # Can't reference config.system.build.uki directly to size the
      # ESP: verityStore overrides it to depend on the intermediate
      # image (for the verity root hash), and the intermediate image's
      # size depends on the ESP → cycle.
      #
      # Solution without IFD: build a parallel "sizing UKI" with the
      # same kernel+initrd+config as the real UKI but without the
      # usrhash cmdline (which is what creates the cycle), and seed it
      # into the ESP contents at the exact path verityStore will later
      # use. At intermediate time repart sees the placeholder and
      # Minimize="guess" (from portable-media-base) sizes the ESP
      # correctly. At finalImage time the verityStore module does a
      # lib.recursiveUpdate on finalPartitions contents with the same
      # path key, replacing the placeholder's .source with the real
      # verity-hashed UKI. The two UKIs differ by ~70 bytes of cmdline
      # (the usrhash=<sha256hex> argument); vfat cluster rounding on a
      # ~100 MB UKI absorbs the difference.
      # See verityStore's finalPartitions override:
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/image/repart-verity-store.nix
      sizingCmdline =
        "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
      sizingUki = pkgs.runCommand "brdboot-immutable-sizing-uki" {
        nativeBuildInputs = [ pkgs.buildPackages.systemdUkify ];
      } ''
        mkdir -p $out
        ukify build \
          --config=${config.boot.uki.configFile} \
          --cmdline="${sizingCmdline}" \
          --output=$out/${ukiFile}
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

    # Enable the single-prompt auth chain for end-to-end testing.
    # Immutable has no LUKS on brd-system, so brdboot-unlock falls back
    # to credential-staging only (no keystore unlock). autoLogin picks
    # up the staged credentials via pam_brdboot_credential and skips
    # the getty prompt.
    #
    # First-boot flow:
    #   1. Initrd prompts for user + password (staged to /run/credentials)
    #   2. dm-verity activates, pivot
    #   3. systemd-homed-firstboot.service prompts for the same user +
    #      password (creates the homed user + LUKS home container)
    #   4. getty@tty1 wrapper reads the staged user, agetty --autologin
    #   5. PAM stack: pam_brdboot_credential sets user/authtok from the
    #      staged credentials; pam_systemd_home unlocks the container
    #
    # Subsequent boots: steps 1, 2, 4, 5 (step 3 runs only once).
    # Type the SAME password at both step 1 and step 3 prompts on
    # first boot or PAM auto-login will reject the mismatch.
    brdboot.singlePrompt.enable = true;
    brdboot.singlePrompt.autoLogin = true;

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
