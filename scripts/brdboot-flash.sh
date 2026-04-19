#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils gawk

# brdboot-flash.sh — canonical flash + verify for brdboot images.
#
# Usage: scripts/brdboot-flash.sh /dev/sdX
#
# Expects a `./result` symlink or directory in the current working
# directory, as produced by:
#
#   nix build .#nixosConfigurations.brdboot.config.system.build.images.<variant>
#
# or for the immutable variant's bootable final image:
#
#   nix build .#nixosConfigurations.brdboot.config.system.build.images.immutable.passthru.config.system.build.finalImage
#
# Looks inside ./result for exactly one *.raw (GPT variants) or
# iso/*.iso (ephemeral). Flashes to the target block device with
# conv=fsync, syncs the kernel page cache, reads the device back,
# and compares SHA-256 hashes byte-for-byte against the source.
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
usage: $0 /dev/sdX

  Expects ./result with a single *.raw or iso/*.iso inside it.
  Run from the directory containing the 'result' symlink.
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage
TARGET=$1

if [[ ! -b $TARGET ]]; then
  echo "error: $TARGET is not a block device" >&2
  exit 1
fi

if [[ ! -d result && ! -L result ]]; then
  echo "error: no './result' in current directory" >&2
  echo "       did you forget to \`nix build\` first?" >&2
  exit 1
fi

# Locate exactly one image. Accept *.raw at the root or iso/*.iso
# for ephemeral. Ignore repart-output.json and other metadata.
shopt -s nullglob
candidates=(result/*.raw result/iso/*.iso)
if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "error: no *.raw or iso/*.iso found under ./result" >&2
  exit 1
elif [[ ${#candidates[@]} -gt 1 ]]; then
  echo "error: more than one image candidate in ./result:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  echo "       unambiguous flash source required; move extras out of result/" >&2
  exit 1
fi
IMAGE=${candidates[0]}
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
