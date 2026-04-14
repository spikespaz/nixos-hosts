{ ... }: {
  image.modules.mutable = { modulesPath, ... }: {
    imports = [ (modulesPath + "/virtualisation/disk-image.nix") ];
    # raw for dd to USB. Default is qcow2 (QEMU only).
    image.format = "raw";
  };
}
