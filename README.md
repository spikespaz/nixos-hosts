# nixos-hosts

NixOS system configurations for personal machines and portable recovery media.

Hosts include a WSL development environment and a bootable USB recovery image with encrypted persistent storage and a read-only system partition.

## brdboot

**B**ootable **R**ecovery & **D**iagnostics — portable NixOS-based recovery image with encrypted persistent storage and a read-only system partition.

### Image variants

| Variant | Description |
|---|---|
| `ephemeral` | Live ISO, no persistent state (squashfs + tmpfs overlay) |
| `mutable` | Writable GPT + ext4, growable after flash |
| `immutable` | Read-only erofs system + persist partition |
| `sealed` | Encrypted erofs system (LUKS) + persist partition |

### Building

All variants are built from the `brdboot` NixOS configuration:

```
nix build .#nixosConfigurations.brdboot.config.system.build.images.<variant>
```

### Flashing

**Ephemeral (ISO):**

```
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
cmp <(sudo dd if=/dev/sdX bs=4M iflag=count_bytes count=$(stat -c%s result/iso/*.iso) 2>/dev/null) result/iso/*.iso && echo OK
```

On Windows, [Rufus](https://rufus.ie) detects the hybrid ISO and offers
DD mode — select it.

**GPT variants (mutable, immutable, sealed):**

```
sudo dd if=result/*.raw of=/dev/sdX bs=4M status=progress conv=fsync
sync
cmp <(sudo dd if=/dev/sdX bs=4M iflag=count_bytes count=$(stat -c%s result/*.raw) 2>/dev/null) result/*.raw && echo OK
```

The `cmp` read-back is strongly recommended on `immutable` — the UKI
cmdline carries `systemd.verity_usr_options=panic-on-corruption`, so
any corrupted block read during boot turns into an immediate kernel
panic. Catch it in ~10 seconds of host-side byte compare rather than
mid-boot on the target. Skip only if you trust the drive and you'd
rather reflash than verify; consumer USB sticks routinely drop bits
during sustained multi-GB writes without the flasher noticing.

On Windows, Rufus does not detect raw images automatically. Select
"All files (\*.\*)" in the file picker to see `.raw` and `.img` files,
then flash in DD mode (the only option for raw images).

After flashing `immutable`, the USB drive has:

```
/dev/sdX
├── /dev/sdX1  brd-esp     (FAT32, 768M)       EFI bootloader
├── /dev/sdX2  brd-system  (erofs, ~var)        Nix store, system closure (read-only)
└── /dev/sdX3  brd-persist (unformatted, 1G+)   Persistent storage (provisioned at first boot)
```

The `sealed` variant wraps the system partition in LUKS.

### LUKS key provisioning (sealed variant)

The sealed image uses `Encrypt = "key-file"` in systemd-repart, which generates a random encryption key at build time. This key is not stored in the output image.

After flashing, the LUKS volume must be re-keyed:

```
sudo cryptsetup luksAddKey /dev/sdX2 --master-key-file <build-key>
```

First-boot provisioning automation is planned.

### CI

Image builds verified by GitHub Actions on every PR and push to master. Artifact deduplication by derivation hash avoids redundant builds.
