{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-wsl, ... }:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor =
        eachSystem (system: import nixpkgs { localSystem.system = system; });
      pkgsCrossFor = localSystem: crossSystem:
        import nixpkgs {
          localSystem.system = localSystem;
          crossSystem.system = crossSystem;
        };
      # Caller modules are ordered before host defaults so callers can
      # use mkOrder and mkOverride to override without fighting evaluation order.
      setImageVersion = false;
      mkBrdboot = { pkgs, modules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit pkgs;
          modules = modules ++ [
            ./hosts/brdboot
            {
              system.image.version = lib.mkIf setImageVersion
                (builtins.substring 0 7 (self.rev or self.dirtyRev or "unknown"));
            }
          ];
        };
    in {
      nixosConfigurations = {
        pathfinder-wsl = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/pathfinder-wsl
          ];
        };

        brdboot = mkBrdboot { pkgs = pkgsFor."x86_64-linux"; };

        brdboot-aarch64 = mkBrdboot { pkgs = pkgsFor."aarch64-linux"; };
      };

      packages = lib.mapAttrs (buildSystem: pkgs:
        let
          brdbootFor = {
            "x86_64-linux" = self.nixosConfigurations.brdboot;
            "aarch64-linux" =
              self.nixosConfigurations.brdboot-aarch64;
          };
          native = lib.optionalAttrs (brdbootFor ? ${buildSystem}) {
            brdboot-images =
              brdbootFor.${buildSystem}.config.system.build.images;
          };
          cross = lib.concatMapAttrs (hostSystem: config:
            lib.optionalAttrs (hostSystem != buildSystem) {
              "brdboot-images-${hostSystem}" = (mkBrdboot {
                pkgs = pkgsCrossFor buildSystem hostSystem;
              }).config.system.build.images;
            }) brdbootFor;
          tests = lib.optionalAttrs (buildSystem == "x86_64-linux") {
            # Clean immutable image with 4 bytes flipped 4 KiB into
            # brd-system — guaranteed inside the first erofs data
            # block the kernel reads at /usr mount. The verity hash
            # tree was baked in by the intermediate stage; this
            # wrapper flips bytes downstream, so tree and data
            # disagree and dm-verity panics on first read.
            #
            # runCommand, not finalImage.overrideAttrs, because
            # in-cwd repart-output.json during postBuild reflects
            # only the finalImage's ESP injection — brd-system isn't
            # in it, so jq matches nothing and the flip lands at
            # byte 0 of the .raw (MBR area, harmless). Wrapping reads
            # the merged output-side repart-output.json, which is
            # authoritative.
            brdboot-immutable-tampered-brd-system =
              let
                clean = self.nixosConfigurations.brdboot
                  .config.system.build.images.immutable
                  .passthru.config.system.build.finalImage;
              in
              pkgs.runCommand "brdboot-immutable-tampered-brd-system" {
                nativeBuildInputs = [ pkgs.jq ];
              } ''
                set -euo pipefail
                mkdir -p $out
                rawIn=$(find ${clean} -maxdepth 1 -name '*.raw' \
                  -printf '%p\n' | head -1)
                rawOut=$out/$(basename "$rawIn")
                echo "copying $rawIn -> $rawOut"
                cp "$rawIn" "$rawOut"
                chmod +w "$rawOut"
                storeOffset=$(jq -r '.[]
                  | select(.label == "brd-system") | .offset' \
                  ${clean}/repart-output.json)
                seekBytes=$((storeOffset + 4096))
                echo "flipping 4 bytes at brd-system + 4096 (offset $seekBytes)"
                printf '\xDE\xAD\xBE\xEF' \
                  | dd of="$rawOut" bs=4 count=1 \
                      seek="$seekBytes" oflag=seek_bytes conv=notrunc
                echo "tamper landed"
              '';
          };
        in native // cross // tests) pkgsFor;

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt-classic) pkgsFor;
    };
}
