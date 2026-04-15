{ ... }: {
  image.modules.immutable = { lib, config, modulesPath, pkgs, ... }: {
    imports = [ (modulesPath + "/image/repart.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    # Grow bb-persist to fill available space on first boot.
    systemd.repart.enable = true;
    systemd.repart.partitions."bb-persist" = {
      Type = "linux-generic";
      Label = "bb-persist";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/disk/by-partlabel/bb-system";
      fsType = "erofs";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/bb-esp";
      fsType = "vfat";
    };

    # TODO: parameterize all bb-* labels and repart name with a
    # per-device UID to avoid conflicts when multiple birdboot
    # drives are connected. Affects: image.repart.name, partition
    # labels (bb-esp, bb-system, bb-persist), and fileSystems entries.
    system.image.id = "${config.system.nixos.distroId}-immutable";

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
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };
      };
      "bb-system" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "linux-generic";
          Format = "erofs";
          Minimize = "guess";
          Label = "bb-system";
        };
      };
      "bb-persist" = {
        repartConfig = {
          Type = "linux-generic";
          SizeMinBytes = "1G";
          Label = "bb-persist";
        };
      };
    };
  };
}
