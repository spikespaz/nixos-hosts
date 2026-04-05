# nixos-hosts

NixOS system configurations for personal machines and portable recovery media.

Hosts include a WSL development environment and a bootable USB recovery image with Secure Boot support, encrypted persistent storage, and a read-only system partition.

## birdboot-portable

Bootable recovery USB image. Read-only NixOS system with encrypted persistent storage on a second partition.

### Image Variants

| Variant | Description |
|---|---|
| `iso-impermanent` | Ephemeral live ISO, no persistent state |

### Building

All variants are built from the `birdboot-portable` NixOS configuration:

```
nix build .#nixosConfigurations.birdboot-portable.config.system.build.images.iso-impermanent
```
