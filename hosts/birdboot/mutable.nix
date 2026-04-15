{ ... }: {
  image.modules.mutable = { lib, config, modulesPath, pkgs, ... }: {
    imports = [ (modulesPath + "/image/repart.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    # Grow bb-root to fill available space on first boot.
    systemd.repart.enable = true;
    systemd.repart.partitions."bb-root" = {
      Type = "root";
      Label = "bb-root";
    };

    fileSystems."/" = {
      device = "/dev/disk/by-partlabel/bb-root";
      fsType = "ext4";
      autoResize = true;
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/bb-esp";
      fsType = "vfat";
    };

    system.image.id = "${config.system.nixos.distroId}-mutable";

    # ${image.id}-${label}-${system}.raw
    image.repart.name = lib.concatStringsSep "-" [
      config.system.image.id
      config.system.nixos.label
      pkgs.stdenv.hostPlatform.system
    ];
    image.repart.partitions = {
      "bb-esp" = {
        contents =
          let
            efiArch = pkgs.stdenv.hostPlatform.efiArch;
          in
          {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          SizeMinBytes = "768M";
          SizeMaxBytes = "768M";
        };
      };
      "bb-root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Minimize = "guess";
          Label = "bb-root";
        };
      };
    };
  };
}
