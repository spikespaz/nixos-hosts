# Shared config for all repart-based portable media variants.
# Provides: systemd-boot + UKI, ESP partition, image naming, runtime grow.
# Each variant imports this and adds its own root filesystem and partitions.
{ lib, config, modulesPath, pkgs, ... }: {
  imports = [ (modulesPath + "/image/repart.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.grub.enable = false;

  systemd.repart.enable = true;

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/bb-esp";
    fsType = "vfat";
  };

  # ${image.id}-${label}-${system}.raw
  image.repart.name = lib.concatStringsSep "-" [
    config.system.image.id
    config.system.nixos.label
    pkgs.stdenv.hostPlatform.system
  ];

  image.repart.partitions."bb-esp" = {
    contents =
      let
        efiArch = pkgs.stdenv.hostPlatform.efiArch;
        ukiFile = config.system.boot.loader.ukiFile;
      in
      {
        "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
          "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
        "/EFI/Linux/${ukiFile}".source =
          "${config.system.build.uki}/${ukiFile}";
        "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
          timeout 5
          default @saved
        '';
      };
    repartConfig = {
      Type = "esp";
      Format = "vfat";
      SizeMinBytes = "768M";
      SizeMaxBytes = "768M";
    };
  };
}
