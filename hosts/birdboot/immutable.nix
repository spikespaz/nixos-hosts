{ ... }: {
  image.modules.immutable = { config, modulesPath, pkgs, ... }: {
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
    image.repart.name = config.networking.hostName;
    image.repart.partitions = {
      "bb-esp" = {
        contents = {
          "/EFI/BOOT/BOOTX64.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
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
