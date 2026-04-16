---
name: nix-architecture
description: Architecture decisions and patterns for this NixOS flake. Documents the pkgsFor/pkgsCrossFor/mkHost factory pattern, image variant system, and module ordering conventions. Read this before modifying flake.nix or adding hosts.
---

# Nix Flake Architecture

This document describes the design patterns in this repository's `flake.nix` and why they exist. Each decision traces to a concrete problem encountered during development.

## Platform abstraction: pkgsFor and pkgsCrossFor

### pkgsFor

```nix
eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
pkgsFor = eachSystem (system: import nixpkgs { localSystem.system = system; });
```

`pkgsFor` is an **attrset** keyed by system string. It produces a native nixpkgs instance for each supported platform. Used for:

- Native `nixosConfigurations` (pass `pkgsFor."x86_64-linux"` to a host factory)
- The `packages` output (iterate with `lib.mapAttrs` to produce per-system package sets)
- The `formatter` output

### pkgsCrossFor

```nix
pkgsCrossFor = localSystem: crossSystem:
  import nixpkgs {
    localSystem.system = localSystem;
    crossSystem.system = crossSystem;
  };
```

`pkgsCrossFor` is a **function**, not an attrset. It takes `localSystem` (the build machine) and `crossSystem` (the target machine) and produces a cross-compilation nixpkgs instance.

**Why a function instead of an attrset?** The cross matrix is `N x M` (build platforms × target platforms). Pre-computing every combination wastes evaluation time and memory. A function is lazily applied only when needed.

**Parameter naming:** `localSystem` and `crossSystem` mirror the nixpkgs `import` parameters they wire into. Earlier iterations used `buildSystem`/`hostSystem` — renamed for directness.

## Host factories: mkBrdboot

```nix
mkBrdboot = { pkgs, modules ? [ ] }: nixpkgs.lib.nixosSystem {
  inherit pkgs;
  modules = modules ++ [ ./hosts/brdboot ];
};
```

### Platform via pkgs, not nixpkgs.hostPlatform

The factory takes `pkgs` (an already-imported nixpkgs instance) rather than a `system` string. This means:

- Platform is determined by `pkgs.stdenv.hostPlatform`, inferred from the nixpkgs import
- No `nixpkgs.hostPlatform` module option needed — avoids a class of infinite recursion bugs where module evaluation depends on config that depends on module evaluation
- The same factory works for both native and cross-compilation — just pass different `pkgs`

### Module ordering: caller before host

```nix
modules = modules ++ [ ./hosts/brdboot ];
```

Caller-provided modules are ordered **before** the host's default modules. This is deliberate:

- NixOS module evaluation respects declaration order for options with the same priority
- Callers can use `mkOrder` and `mkOverride` to override host defaults without fighting evaluation order
- If host defaults came first, callers would need higher override levels to win, creating a priority arms race

### Why not specialArgs?

Earlier iterations passed the nixpkgs source path via `specialArgs`. This was removed because:

- `pkgs` is already available as a module argument (set by `nixpkgs.lib.nixosSystem`)
- `pkgs.path` provides the nixpkgs source root — no extra plumbing needed
- `modulesPath` (from `lib.evalModules`) provides the NixOS modules directory for imports — config-independent, no recursion risk

## Image variant system: image.modules

```nix
# hosts/brdboot/ephemeral.nix
{ ... }: {
  image.modules.ephemeral = { modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/cd-dvd/iso-image.nix") ];
    isoImage.squashfsCompression = "zstd -Xcompression-level 19";
  };
}
```

### Deferred modules

Each image variant is a **deferred module** — a function assigned to `image.modules.<name>`. The NixOS image infrastructure evaluates these in isolated contexts via `extendModules`, meaning:

- Each variant gets its own evaluation scope
- Variants don't interfere with each other's options
- The base `nixosConfiguration` carries all variants but builds them independently

### modulesPath, not pkgs.path

Imports inside deferred modules **must not** reference `pkgs`. In `imports = [...]`, the module system resolves imports before `config` is available. Since `pkgs` depends on `config` (via `_module.args`), using `pkgs.path` in imports creates infinite recursion.

`modulesPath` is a config-independent argument set by `lib.evalModules` (defined in `nixos/lib/eval-config.nix`). It points to the NixOS modules directory and is always safe to use in imports.

### One file per variant

Each variant lives in its own file under `hosts/<host>/`:

```
hosts/brdboot/
├── default.nix              # system identity, hardware, nix settings
├── portable-media-base.nix  # shared repart: bootloader, ESP, UKI, naming
├── ephemeral.nix            # live ISO (squashfs+tmpfs, no persistence)
├── mutable.nix              # writable ext4 root (imports portable-media-base)
├── immutable.nix            # read-only erofs root (imports portable-media-base)
└── sealed.nix               # encrypted erofs root (imports portable-media-base)
```

`default.nix` imports variant files. This separation means:

- Each variant can be added or removed by editing one import line
- Variant files are independently reviewable
- The minimal branch (#6) was created by simply removing imports

## Packages output: the cross-build bridge

```nix
packages = lib.mapAttrs (buildSystem: pkgs:
  let
    hostSystem = "x86_64-linux";
    isCross = buildSystem != hostSystem;
    name = "brdboot-images"
      + lib.optionalString isCross "-${hostSystem}";
    images = if isCross then
      let pkgs = pkgsCrossFor buildSystem hostSystem;
      in (mkBrdboot { inherit pkgs; }).config.system.build.images
    else
      self.nixosConfigurations.brdboot.config.system.build.images;
  in { ${name} = images; }) pkgsFor;
```

### Native vs cross

- **Native** (`buildSystem == hostSystem`): references `self.nixosConfigurations.brdboot` directly — no redundant evaluation
- **Cross** (`buildSystem != hostSystem`): creates a fresh `mkBrdboot` with cross-compiled `pkgs`, suffixed with `-${hostSystem}` to distinguish from the native package

### Why packages, not just nixosConfigurations?

`nix build .#packages.aarch64-linux.brdboot-images-x86_64-linux.ephemeral` works from an aarch64 machine. The `packages` output maps build platforms to their available targets, making CI matrix entries straightforward — each runner builds with its native `packages.<system>`.

## Patterns to follow when adding hosts

1. **Create a factory function** in the `let` block: `mkHostname = { pkgs, modules ? [] }: nixpkgs.lib.nixosSystem { ... };`
2. **Pass `pkgs`**, never set `nixpkgs.hostPlatform` or `system` in modules
3. **Order caller modules before host defaults** in the factory
4. **Use `modulesPath`** for imports in deferred modules, never `pkgs.path`
5. **One file per image variant**, imported from `default.nix`
6. **Add to `packages` output** with cross-build support if the host targets a specific platform
