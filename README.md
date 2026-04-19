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

Ephemeral, mutable, and sealed variants build directly from the
`brdboot` NixOS configuration:

```
nix build .#nixosConfigurations.brdboot.config.system.build.images.<variant>
```

The `immutable` variant uses a three-stage verity pipeline
(intermediate → UKI → final); the bootable artifact is the final
stage, which the `system.build.finalImage` passthru exposes:

```
nix build .#nixosConfigurations.brdboot.config.system.build.images.immutable.passthru.config.system.build.finalImage
```

Substitute `brdboot-aarch64` for `brdboot` to target aarch64 instead
of x86_64 (cross-built from the build host's arch).

Each invocation produces a `result` symlink — that's what the flash
script below expects.

### Flashing

Canonical procedure — `dd` with `conv=fsync`, then sync, then SHA-256
verify the bytes that actually landed on the drive:

```
./scripts/brdboot-flash.sh /dev/sdX               # auto-discover ./result/
./scripts/brdboot-flash.sh /dev/sdX path/to.raw   # explicit image path
```

The script picks up the single image inside `./result` (either
`result/*.raw` for GPT variants or `result/iso/*.iso` for ephemeral),
flashes it, reads the device back, and exits non-zero on any mismatch
with guidance pointing at common failure modes (weak flash cells,
sustained-write degradation past the SLC cache, transient USB protocol
errors). The script is `nix-shell`-shebanged, so `nix-shell` is the
only host dependency.

Skipping the verify step isn't recommended: consumer USB sticks
routinely drop bits during sustained multi-GB writes without the flasher
noticing. On the `immutable` variant the UKI cmdline carries
`systemd.verity_usr_options=panic-on-corruption`, so any corrupted
block read during boot turns into an immediate kernel panic — a loud
signal, but one you'd rather catch in 10 seconds of host-side SHA-256
check than mid-boot on the target hardware. On non-verity variants
silent flash corruption is worse: files on disk just break
unpredictably, with no kernel-level tripwire.

**Manual equivalent if you prefer bare commands:**

```
# Ephemeral (ISO)
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M conv=fsync status=progress
sync
cmp <(sudo dd if=/dev/sdX bs=4M iflag=count_bytes count=$(stat -c%s result/iso/*.iso) 2>/dev/null) result/iso/*.iso && echo OK

# GPT variants (mutable / immutable / sealed)
sudo dd if=result/*.raw of=/dev/sdX bs=4M conv=fsync status=progress
sync
cmp <(sudo dd if=/dev/sdX bs=4M iflag=count_bytes count=$(stat -c%s result/*.raw) 2>/dev/null) result/*.raw && echo OK
```

**Windows (two paths):**

Option A — [Rufus](https://rufus.ie) in DD mode. Rufus detects the
hybrid ISO and offers DD mode directly. For the `.raw` GPT variants
Rufus doesn't auto-detect — select "All files (\*.\*)" in the file
picker, then flash in DD mode (the only option for raw images).
Straightforward, no WSL dependency, but doesn't verify after flash
— fall back to the manual `cmp` block above if the drive is worth
catching corruption on.

Option B — WSL + the PowerShell wrapper, requires WSL installed:

```
.\scripts\brdboot-flash.ps1 -Disk <N>
```

The wrapper attaches `\\.\PHYSICALDRIVE<N>` to WSL via `wsl --mount
--bare`, invokes `brdboot-flash.sh` inside WSL so the flash and
SHA-256 verify run as on a native Linux host, and detaches on exit.
Must be run in an elevated PowerShell. Find the disk number with
`Get-Disk` in PowerShell.

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
