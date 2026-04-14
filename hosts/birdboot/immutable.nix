{ ... }: {
  image.modules.immutable = { config, modulesPath, pkgs, ... }: {
    imports = [ (modulesPath + "/image/repart.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/disk/by-label/nixos-system";
      fsType = "squashfs";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/10-esp";
      fsType = "vfat";
    };

    image.repart.name = "birdboot-portable";
    image.repart.partitions = {
      "10-esp" = {
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
      "20-system" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "linux-generic";
          Format = "squashfs";
          Minimize = "guess";
          Label = "nixos-system";
        };
      };
      "30-persist" = {
        repartConfig = {
          Type = "linux-generic";
          SizeMinBytes = "1G";
          Label = "persist";
        };
      };
    };
  };
}
