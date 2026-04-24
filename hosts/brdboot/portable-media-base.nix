# Shared config for all repart-based portable media variants.
# Provides: systemd-boot, ESP partition, image naming, runtime grow.
# Each variant imports this and adds its own root filesystem, partitions,
# and UKI injection into the ESP.
#
# Note: UKI injection is deferred to variants because the verityStore
# module injects the UKI via finalImage override. Referencing
# config.system.build.uki here would create a dependency cycle:
#   image → uki (from ESP contents) → intermediateImage → image.
{ lib, config, modulesPath, pkgs, ... }: {
  imports = [ (modulesPath + "/image/repart.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.grub.enable = false;

  # Partition grow at boot is handled by systemd-repart (see per-variant
  # systemd.repart.partitions entries); disable the alternative
  # growPartition service explicitly so no future import races repart
  # for the GPT header. Use lib.mkForce to re-enable.
  boot.growPartition = lib.mkImageMediaOverride false;

  systemd.repart.enable = true;

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/brd-esp";
    fsType = "vfat";
  };

  # ${image.id}-${label}-${system}.raw
  image.repart.name = lib.concatStringsSep "-" [
    config.system.image.id
    config.system.nixos.label
    pkgs.stdenv.hostPlatform.system
  ];

  # Upstream repart-image.nix constructs image.baseName as
  # "${image.repart.name}_${version}" — an underscore between arch
  # and version. Override to use a dash instead, matching ephemeral
  # and the general nix convention "${name}-${version}". Use
  # mkImageMediaOverride so a downstream deployment can still mkForce.
  image.baseName = lib.mkImageMediaOverride (lib.concatStringsSep "-" (
    [
      config.system.image.id
      config.system.nixos.label
      pkgs.stdenv.hostPlatform.system
    ] ++ lib.optional (config.system.image.version != null)
      config.system.image.version
  ));

  image.repart.partitions."00-brd-esp" = {
    contents =
      let
        efiArch = pkgs.stdenv.hostPlatform.efiArch;
      in
      {
        "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
          "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
        "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
          timeout 5
          default @saved
        '';
      };
    repartConfig = {
      Type = "esp";
      Format = "vfat";
      Label = "brd-esp";
      # On vfat (read-write), repart rejects "best"; guess is the fallback.
      # Variants that defer UKI injection to finalImage (e.g. via verityStore)
      # must seed a placeholder at the UKI path so there's content for repart
      # to measure at intermediate time.
      Minimize = "guess";
    };
  };
}
