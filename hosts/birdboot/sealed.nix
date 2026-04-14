{ ... }: {
  image.modules.sealed = { lib, config, modulesPath, pkgs, ... }: {
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

    boot.initrd.luks.devices."bb-system" = {
      device = "/dev/disk/by-partlabel/bb-system";
    };

    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };
    fileSystems."/nix/store" = {
      device = "/dev/mapper/bb-system";
      fsType = "erofs";
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/bb-esp";
      fsType = "vfat";
    };

    # TODO: parameterize all bb-* labels, repart name, and LUKS
    # device name (bb-system) with a per-device UID to avoid
    # conflicts when multiple birdboot drives are connected.
    # birdboot-sealed-<label>-<system>.raw
    image.repart.name = lib.concatStringsSep "-" [
      config.system.nixos.distroId
      "sealed"
      config.system.nixos.label
      pkgs.stdenv.hostPlatform.system
    ];
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
          Encrypt = "key-file";
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
