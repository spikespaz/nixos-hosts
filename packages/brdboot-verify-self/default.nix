{ writeShellApplication, coreutils, util-linux, cryptsetup, gawk }:

writeShellApplication {
  name = "brdboot-verify-self";
  runtimeInputs = [ coreutils util-linux cryptsetup gawk ];
  text = ''
    # Identity + integrity self-check for a booted brdboot immutable
    # system. Reads the dm-verity root hash from /proc/cmdline (placed
    # there by the UKI the kernel booted from) and runs `veritysetup
    # verify` against the brd-system and brd-system-verity partitions
    # of the drive we booted from.
    #
    # Confirms two things:
    #   1. Identity — the booted kernel's embedded root hash is what
    #      you expect from the image you thought you flashed. Mismatch
    #      means you booted a different build than you thought.
    #   2. Integrity — the bytes currently stored on the drive still
    #      hash correctly to that root. Mismatch with a previously-
    #      passing SHA-256 readback is the signature of consumer-flash
    #      post-write drift (SLC->TLC migration bit errors).
    #
    # Reads the raw partition devices through the same USB/SD/SATA code
    # path the kernel uses. Does not conflict with the active dm-verity
    # mapping on top — veritysetup verify only reads; it does not
    # activate a second mapping.

    set -euo pipefail

    if [[ $EUID -ne 0 ]]; then
      echo "error: run as root (partitions are not world-readable)" >&2
      exit 1
    fi

    ROOTHASH=$(awk -v RS=' ' '/^usrhash=/ {sub("usrhash=", ""); print}' /proc/cmdline)
    if [[ -z "$ROOTHASH" ]]; then
      echo "error: no usrhash= on /proc/cmdline — is this an immutable boot?" >&2
      exit 1
    fi

    DATA=/dev/disk/by-partlabel/brd-system
    HASH=/dev/disk/by-partlabel/brd-system-verity

    if [[ ! -e "$DATA" || ! -e "$HASH" ]]; then
      echo "error: brd-system / brd-system-verity not under /dev/disk/by-partlabel" >&2
      exit 1
    fi

    DATA_REAL=$(readlink -f "$DATA")
    HASH_REAL=$(readlink -f "$HASH")

    echo "root hash: $ROOTHASH"
    echo "data:      $DATA -> $DATA_REAL"
    echo "hash:      $HASH -> $HASH_REAL"
    echo
    echo "running veritysetup verify (reads the full data partition)..."

    exec veritysetup verify "$DATA_REAL" "$HASH_REAL" "$ROOTHASH"
  '';
}
