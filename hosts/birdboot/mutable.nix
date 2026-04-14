{ ... }: {
  image.modules.mutable = { config, modulesPath, pkgs, ... }: {
    imports = [ (modulesPath + "/image/repart.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    fileSystems."/" = {
      device = "/dev/disk/by-partlabel/bb-root";
      fsType = "ext4";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/bb-esp";
      fsType = "vfat";
    };

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
          # Grows to fill available space at first boot via
          # boot.initrd.systemd.repart or systemd-growfs.
        };
      };
    };
  };
}
