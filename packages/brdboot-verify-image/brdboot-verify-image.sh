#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils util-linux jq cryptsetup systemdUkify mtools findutils

# Verify the dm-verity hash tree of a brdboot immutable image
# against the root hash embedded in the UKI cmdline.
#
# Works against a `finalImage` output (the flashable .raw) by
# extracting the UKI straight out of brd-esp via mtools — no loop
# device, no mount — so the derivation can also run in a Nix build
# sandbox as a `checks.<system>` entry. brd-system and brd-system-
# verity partitions are likewise extracted via dd, and the hash-tree
# check is `veritysetup verify`.
#
# Catches image-side corruption — i.e., bugs in the build pipeline
# that could produce a hash tree that doesn't cryptographically match
# the data partition's bytes. The upstream repart-verity-store module
# only runs a metadata cross-check (assert_uki_repart_match.py
# compares the UKI cmdline's `usrhash=` string against
# repart-output.json's `roothash` field), not a real veritysetup
# verify.
#
# Usage:
#   brdboot-verify-image [path]
#
# With no argument, defaults to ./result. Accepts either a directory
# containing a *.raw, or a path to the *.raw directly.

set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [result-dir-or-raw]" >&2
  exit 1
fi

ARG=${1:-./result}

if [[ -d $ARG ]]; then
  IMG=$(find "$ARG" -maxdepth 2 -name '*.raw' -type f | head -1)
elif [[ -f $ARG ]]; then
  IMG=$ARG
else
  echo "error: $ARG is not a file or directory" >&2
  exit 1
fi

if [[ -z ${IMG:-} ]]; then
  echo "error: no *.raw found under $ARG" >&2
  exit 1
fi

echo "image: $IMG"

PARTS=$(sfdisk -J "$IMG")
read -r ESP_OFF  ESP_SZ  < <(jq -r '
  .partitiontable.partitions[]
  | select(.name == "brd-esp")
  | "\(.start) \(.size)"' <<<"$PARTS")
read -r DATA_OFF DATA_SZ < <(jq -r '
  .partitiontable.partitions[]
  | select(.name == "brd-system")
  | "\(.start) \(.size)"' <<<"$PARTS")
read -r HASH_OFF HASH_SZ < <(jq -r '
  .partitiontable.partitions[]
  | select(.name == "brd-system-verity")
  | "\(.start) \(.size)"' <<<"$PARTS")

if [[ -z ${ESP_OFF:-} || -z ${DATA_OFF:-} || -z ${HASH_OFF:-} ]]; then
  echo "error: brd-esp / brd-system / brd-system-verity partitions" >&2
  echo "       not found in $IMG. Not an immutable variant, or" >&2
  echo "       labels differ." >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "extracting brd-esp           ($ESP_SZ sectors @ $ESP_OFF)..."
dd if="$IMG" of="$TMP/esp.img" bs=512 \
   skip="$ESP_OFF" count="$ESP_SZ" status=none

# UKI location inside the ESP: systemd-boot convention is
# EFI/Linux/*.efi (type-2 boot entries); fall back to EFI/BOOT.
UKI_PATH=$(mdir -i "$TMP/esp.img" -b ::/EFI/Linux 2>/dev/null \
  | grep -iE '\.efi$' | head -1 || true)
if [[ -z ${UKI_PATH:-} ]]; then
  UKI_PATH=$(mdir -i "$TMP/esp.img" -b ::/EFI/BOOT 2>/dev/null \
    | grep -iE '\.efi$' | head -1 || true)
fi
if [[ -z ${UKI_PATH:-} ]]; then
  echo "error: no *.efi found in brd-esp under EFI/Linux or EFI/BOOT" >&2
  exit 1
fi
# mdir -b prints full mtools paths like "::/EFI/Linux/foo.efi"
mcopy -i "$TMP/esp.img" "$UKI_PATH" "$TMP/uki.efi"
echo "UKI:   $UKI_PATH (extracted from brd-esp)"

ROOTHASH=$(ukify inspect "$TMP/uki.efi" --json=short \
  | jq -r '.[".cmdline"].text' \
  | tr ' ' '\n' \
  | sed -n 's/^usrhash=//p')

if [[ -z ${ROOTHASH:-} ]]; then
  echo "error: could not extract usrhash= from UKI cmdline" >&2
  exit 1
fi

echo "root:  $ROOTHASH"

echo "extracting brd-system        ($DATA_SZ sectors @ $DATA_OFF)..."
dd if="$IMG" of="$TMP/data.img" bs=512 \
   skip="$DATA_OFF" count="$DATA_SZ" status=none

echo "extracting brd-system-verity ($HASH_SZ sectors @ $HASH_OFF)..."
dd if="$IMG" of="$TMP/hash.img" bs=512 \
   skip="$HASH_OFF" count="$HASH_SZ" status=none

echo "running veritysetup verify..."
veritysetup verify "$TMP/data.img" "$TMP/hash.img" "$ROOTHASH"

echo "OK: hash tree matches root hash"
