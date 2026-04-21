{ pkgs, ... }: {
  imports = [
    # Variant deferred modules
    ./ephemeral.nix
    ./mutable.nix
    ./immutable.nix
    ./sealed.nix

    # Shared infrastructure (gated behind brdboot.* options, default off).
    ./homed.nix
    ./single-prompt-boot.nix
  ];

  system.stateVersion = "25.05";

  # ID in os-release(5), lsb-release DISTRIB_ID, DEFAULT_HOSTNAME.
  # Changing from "nixos" automatically sets ID_LIKE = "nixos" so
  # tooling that checks for NixOS compatibility still works.
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L121-L126
  system.nixos.distroId = "brdboot";

  # NAME and PRETTY_NAME in os-release(5), syslinux/grub boot menu
  # title and entry labels. Default is "NixOS" (capitalized).
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L128-L133
  system.nixos.distroName = "Brdboot";

  # VARIANT_ID and VARIANT in os-release(5).
  # https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/misc/version.nix#L135-L147
  system.nixos.variant_id = "portable-recovery";
  system.nixos.variantName = "Brdboot: Portable Recovery";

  networking.hostName = "brdboot";

  # Load initrd modules for all common storage controllers (AHCI, NVMe,
  # USB, SCSI, SD, virtio, VMware, Hyper-V) and bundle redistributable
  # firmware (linux-firmware, WiFi, audio). Without this the ISO can't
  # find its own USB stick on most hardware — the initrd only has
  # squashfs, iso9660, uas, overlay, loop by default.
  # See: https://github.com/NixOS/nixpkgs/blob/8110df5ad7abf5d4c0f6fb0f8f978390e77f9685/nixos/modules/hardware/all-hardware.nix
  hardware.enableAllHardware = true;

  # Filesystem support for recovery — mount and inspect drives from
  # any machine this boots on.
  boot.supportedFilesystems = [
    # -- variant-module defaults, listed here so the full picture is
    #    visible and they're enabled regardless of which variant runs --
    "vfat"     # ESP boot partition (portable-media-base.nix)
    "ext4"     # mutable variant root
    "erofs"    # immutable/sealed variant system partition
    "tmpfs"    # immutable/sealed variant root overlay
    # -- iso-image.nix filesystems, explicitly enabled --
    "squashfs" # compressed read-only root
    "iso9660"  # ISO filesystem

    # -- recovery targets --
    "btrfs"    # copy-on-write, snapshots, checksums — default on many Linux distros
    "cifs"     # SMB/CIFS network shares (Windows, NAS, Samba)
    "exfat"    # USB sticks, SD cards, cross-platform (native kernel ≥5.7)
    "f2fs"     # flash-optimized — Android, embedded, some Chromebooks
    "jfs"      # IBM journaled FS — rare but still found on older enterprise systems
    "ntfs"     # Windows drives via FUSE ntfs3g — slower than native, but full R/W
    "xfs"      # RHEL/CentOS default — large file performance, common on servers
    # "bcachefs" — on-disk format drifts across kernel versions, not portable for recovery
    "apfs"     # Apple APFS — read-only, out-of-tree kernel module (experimental)
  ];

  # Filesystems without dedicated NixOS modules.
  # Kernel modules are built-in; userspace tools added manually.
  boot.kernelModules = [
    "hfsplus" # macOS HFS+ — older Macs, Time Machine backups (R/W but no journaling)
    "udf"     # Universal Disk Format — DVDs, Blu-ray, large USB (≥2TB FAT alternative)
    "ntfs3"   # native kernel NTFS driver (≥5.15) — faster than FUSE ntfs3g for reads
  ];
  environment.systemPackages = with pkgs; [
    hfsprogs  # mkfs.hfsplus, fsck.hfsplus
    udftools  # mkudffs, udfinfo, udflabel

    # Partition-table reconstruction (`testdisk`) + file carving (`photorec`).
    testdisk

    # SMART disk health: `smartctl -a /dev/sdX` triages drive failures.
    smartmontools

    # NTFS userspace: `ntfsfix` clears dirty bit, `ntfsundelete`
    # recovers MFT entries — offline complement to kernel ntfs3.
    ntfs3g
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
      # Dynamically allocate build UIDs from user namespaces
      # (872415232+ on Linux) instead of creating persistent
      # nixbld{1..N} entries in /etc/passwd (NixOS default: 32
      # system users at UIDs 30001-30032). NixOS's nix-daemon module
      # makes nrBuildUsers conditional on this flag and falls back
      # to 0 when it is set — nix builds still work because the
      # sandbox allocates UIDs on demand.
      #
      # The motivation is upstream of brdboot: systemd-userdb
      # classifies any user with UID >= 1000 (systemd's
      # SYSTEM_UID_MAX) as "regular" and systemd-homed-firstboot
      # refuses to prompt for account creation when regular users
      # already exist. nixbld's default UID of 30000 trips that
      # check. Removing the persistent users entirely avoids the
      # conflict; downstream homed.nix likewise needs no
      # services.userdbd.silenceHighSystemUsers workaround since
      # there are no high system users to silence warnings about.
      #
      # Recovery images otherwise wouldn't need persistent build
      # users at runtime — immutable/sealed stores are kernel-
      # enforced RO (verity / erofs-in-LUKS); ephemeral is squashfs
      # RO; mutable alone could build, and only after remounting
      # the store rw. Build capability is preserved via namespace-
      # allocated UIDs anyway, so field rebuilds aren't precluded:
      # nix stays a first-class tool on the deployed image.
      #
      # Experimental feature. Adoption decision, known issues, and
      # exit criteria tracked in #41. Fallback if the feature
      # regresses: drop this list entry and the auto-allocate-uids
      # toggle below, set ids.uids.nixbld = 350.
      "auto-allocate-uids"
    ];

    # Toggle the actual behavior — the experimental-features entry
    # above merely permits it.
    auto-allocate-uids = true;
  };

  # Stopgap so HW-test logins work before homed-based account creation
  # lands. Flashed images accept `root` / `password` at the tty1 prompt,
  # which is enough to run `dmesg | grep verity`, `findmnt /usr`, and
  # confirm the verity activation + tamper-detection paths.
  #
  # To be cleaned up once the homed-enablement PR (carved from #36)
  # introduces proper per-user encrypted homes and a first-boot prompt.
  users.users.root.initialPassword = "password";
}
