#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils gawk

# brdboot-flash.sh — canonical flash + verify for brdboot images.
#
# Usage: scripts/brdboot-flash.sh /dev/sdX [image]
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
usage: $0 /dev/sdX [image]

  /dev/sdX  block device to flash
  image     optional path to a .raw or .iso image. when omitted,
            auto-discovered as ./result/*.raw or ./result/iso/*.iso
            (from nix build's default output symlink).
EOF
  exit 1
}

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

echo "flashing $IMAGE ($SIZE bytes) -> $TARGET"
# dd's status=progress stops updating once all bytes are handed to the
# kernel, then `conv=fsync` blocks at close waiting for the drive to
# ack the write — on a slow USB stick this can sit at 100% for a
# minute or more. That's normal; let it finish.
sudo dd if="$IMAGE" of="$TARGET" bs=4M conv=fsync status=progress
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
  1. Try a different USB port / cable (transient protocol error?)
  2. Try a different USB stick (weak cells / fake capacity?)
  3. nix shell nixpkgs#f3 -c f3probe --destructive $TARGET
EOF
  exit 2
fi
