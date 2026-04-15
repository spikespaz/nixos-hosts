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
    system.image.id = "${config.system.nixos.distroId}-sealed";

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
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };
      };
      # System partition is erofs inside LUKS. systemd-repart creates
      # the LUKS container with a random key-file at build time.
      # The build-time key is NOT stored in the output image.
      #
      # After flashing to USB, the LUKS volume must be re-keyed:
      #   sudo cryptsetup luksFormat /dev/sdX2
      #
      # At boot, the initrd prompts for the LUKS passphrase via
      # boot.initrd.luks.devices."bb-system" (defined above).
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
