#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils gawk pv

# brdboot-flash.sh — canonical flash + verify for brdboot images.
#
# Usage: scripts/brdboot-flash.sh [--strict] [--rate=N] /dev/sdX [image]
#
# With no image argument, expects a `./result` symlink or directory in
# the current working directory (as produced by nix build) and picks
# up exactly one *.raw at the root or iso/*.iso. With an explicit
# second argument, uses that file directly and skips the ./result
# lookup — useful for flashing pre-downloaded artifacts (CI, older
# builds, one-off images).
#
# Image sources:
#
#   nix build .#nixosConfigurations.brdboot.config.system.build.images.<variant>
#   nix build .#nixosConfigurations.brdboot.config.system.build.images.immutable.passthru.config.system.build.finalImage
#
# Flashes to the target block device with conv=fsync, syncs the
# kernel page cache, reads the device back, and compares SHA-256
# hashes byte-for-byte against the source.
#
# --strict mode swaps bs=4M conv=fsync for bs=1M oflag=direct,sync
# conv=fsync,fdatasync — kernel hands buffers straight to the block
# device with no page-cache layer, and every write call blocks until
# the drive acknowledges. Slower (~2-3×) but reduces the window where
# cheap drives can buffer-and-lose writes. Use when the default has
# produced hash mismatches even after eject/replug, or when boot
# fails on a drive whose post-flash hash matches (suggests dm-verity
# is hitting a write-pattern not exposed by sequential cmp readback).
#
# --rate=N caps write throughput by piping the image through `pv -L N`
# (pv accepts standard suffixes: 30M, 1G, etc.). Useful on drives
# whose SLC cache fills mid-write and the controller falls back to
# slower QLC/TLC writes that can get reordered or silently dropped.
# Capping below the SLC drain rate keeps writes in the SLC tier.
# Composes with --strict — the throttle just feeds dd's stdin slower.
#
# Hash mismatch means the flash landed corrupt bytes on the stick —
# a common failure mode on cheap or aging USB drives (SLC cache
# exhaustion in the back half of a sustained write, weak flash
# cells, transient USB errors). When it happens:
#
#   (a) try a different USB port / cable
#   (b) try a different USB stick
#   (c) run `f3probe --destructive /dev/sdX` (from nixpkgs#f3) to
#       test the drive itself
#
# Rufus DD mode on Windows has historically produced verify
# failures on this project's images; WSL with `wsl --mount --bare`
# plus this script is the recommended flash path from Windows.

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 [--strict] [--rate=N] /dev/sdX [image]

  --strict  use stricter dd flags (bs=1M, oflag=direct,sync,
            conv=fsync,fdatasync) for hardened writes on cheap or
            UAS-quirky USB drives. Slower but more reliable.

  --rate=N  cap write rate to N bytes/sec by piping the image through
            \`pv -L N\`. N accepts standard suffixes (e.g. 30M, 1G).
            Useful when a drive's SLC cache fills and falls back to
            slow QLC/TLC writes that drop or reorder.

  /dev/sdX  block device to flash
  image     optional path to a .raw or .iso image. when omitted,
            auto-discovered as ./result/*.raw or ./result/iso/*.iso
            (from nix build's default output symlink).
EOF
  exit 1
}

STRICT=0
RATE=
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict) STRICT=1; shift ;;
    --rate=*) RATE="${1#--rate=}"; shift ;;
    --rate)
      [[ $# -ge 2 ]] || { echo "error: --rate requires a value" >&2; usage; }
      RATE=$2
      shift 2
      ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option: $1" >&2; usage ;;
    *) break ;;  # positional args follow
  esac
done

[[ $# -ge 1 && $# -le 2 ]] || usage
TARGET=$1
IMAGE=${2:-}

if [[ ! -b $TARGET ]]; then
  echo "error: $TARGET is not a block device" >&2
  exit 1
fi

if [[ -n $IMAGE ]]; then
  # Explicit image argument — validate it exists and is a regular file.
  if [[ ! -f $IMAGE ]]; then
    echo "error: $IMAGE is not a regular file" >&2
    exit 1
  fi
else
  # Auto-discover under ./result/. Accept *.raw at the root or
  # iso/*.iso for ephemeral. Ignore repart-output.json etc.
  if [[ ! -d result && ! -L result ]]; then
    echo "error: no './result' in current directory and no image arg" >&2
    echo "       did you forget to \`nix build\` first?" >&2
    echo "       (or pass the image path as a second argument)" >&2
    exit 1
  fi

  shopt -s nullglob
  candidates=(result/*.raw result/iso/*.iso)
  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "error: no *.raw or iso/*.iso found under ./result" >&2
    echo "       pass an explicit image path as a second argument if it's" >&2
    echo "       located elsewhere" >&2
    exit 1
  elif [[ ${#candidates[@]} -gt 1 ]]; then
    echo "error: more than one image candidate in ./result:" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    echo "       pass the intended one as an explicit second argument" >&2
    exit 1
  fi
  IMAGE=${candidates[0]}
fi
SIZE=$(stat -c%s "$IMAGE")

mode_label=""
(( STRICT )) && mode_label+=" strict"
[[ -n $RATE ]] && mode_label+=" rate=$RATE"
echo "flashing $IMAGE ($SIZE bytes) -> $TARGET${mode_label:+ (}${mode_label# }${mode_label:+)}"

if (( STRICT )); then
  DD_FLAGS=(bs=1M oflag=direct,sync conv=fsync,fdatasync status=progress)
else
  DD_FLAGS=(bs=4M conv=fsync status=progress)
fi
# dd's status=progress stops updating once all bytes are handed to the
# kernel, then `conv=fsync` blocks at close waiting for the drive to
# ack the write — on a slow USB stick this can sit at 100% for a
# minute or more. That's normal; let it finish. Strict mode is even
# slower because every write call blocks on the drive's ack, not just
# the close.
if [[ -n $RATE ]]; then
  # pv throttles dd's stdin; with oflag=sync (in strict) writes can't
  # outrun the input rate, so this caps actual throughput to the drive.
  pv -L "$RATE" "$IMAGE" | sudo dd of="$TARGET" "${DD_FLAGS[@]}"
else
  sudo dd if="$IMAGE" of="$TARGET" "${DD_FLAGS[@]}"
fi
sync

echo
echo "verifying: reading back $SIZE bytes from $TARGET..."
SRC_HASH=$(sha256sum "$IMAGE" | awk '{print $1}')
# `iflag=count_bytes` makes `count=$SIZE` bytes rather than blocks, so dd
# reads exactly $SIZE bytes and closes stdout cleanly. Previously this
# was `count=$BLOCKS | head -c $SIZE`, which SIGPIPE'd dd as soon as head
# had taken its $SIZE bytes — under `set -o pipefail` that surfaces as
# exit 141 and aborts the verify before the hash comparison.
DST_HASH=$(sudo dd if="$TARGET" bs=4M iflag=count_bytes count="$SIZE" 2>/dev/null \
  | sha256sum \
  | awk '{print $1}')

echo
echo "  source:  $SRC_HASH  $IMAGE"
echo "  flashed: $DST_HASH  $TARGET (first $SIZE bytes)"
echo

if [[ $SRC_HASH == "$DST_HASH" ]]; then
  echo "OK: hashes match — flash verified"
  exit 0
else
  cat >&2 <<EOF
FAIL: hash mismatch — the bytes on $TARGET do not match $IMAGE.

Next steps:
  1. Re-flash with --strict (slower writes, fewer drive-side bugs):
     $0 --strict $TARGET${IMAGE:+ $IMAGE}
  2. Re-flash with --strict --rate=30M (also caps to SLC-cache speed):
     $0 --strict --rate=30M $TARGET${IMAGE:+ $IMAGE}
  3. Try a different USB port / cable (transient protocol error?)
  4. Try a different USB stick (weak cells / fake capacity?)
  5. nix shell nixpkgs#f3 -c f3probe --destructive $TARGET
EOF
  exit 2
fi
