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

  image.repart.partitions."brd-esp" = {
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
      SizeMinBytes = "768M";
      SizeMaxBytes = "768M";
    };
  };
}
