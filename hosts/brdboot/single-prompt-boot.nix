# Initrd-side logic for single-prompt boot authentication.
#
# When enabled, the initrd:
#   1. Mounts brd-persist read-only at /brdboot-persist
#   2. Prompts the user for username and password
#   3. Opens /brdboot-persist/keystores/<username>.keystore with the password,
#      revealing the deployment key that unlocks brd-system
#   4. Stages the deployment key for systemd-cryptsetup@brd-system
#   5. Stages the username and password as systemd credentials for later
#      consumption by a PAM auto-login wrapper (wired in commit 5)
#   6. Unmounts brd-persist — it will be re-mounted by the booted system
#
# The keystore pattern lets each user have a distinct password that
# indirectly unlocks the shared deployment-keyed system partition.
# Revocation is deleting the user's .keystore file — their password
# no longer opens anything, but the deployment key continues to work
# for other users' keystores.
{ lib, pkgs, config, ... }:
let
  cfg = config.brdboot.singlePrompt;

  unlockScript = pkgs.writeShellApplication {
    name = "brdboot-unlock";
    runtimeInputs = with pkgs; [
      systemd    # systemd-ask-password
      cryptsetup # cryptsetup open/close
      util-linux # mount/umount
      coreutils  # mkdir, cat, rm, install
    ];
    text = ''
      set -euo pipefail

      PERSIST_DEV="${cfg.persistPartition}"
      SYSTEM_DEV="${cfg.systemLuksPartition}"
      PERSIST_MNT="/brdboot-persist"
      DEPLOY_KEY="/run/brdboot/deploy.key"
      CREDS_DIR="/run/credentials/@system"

      mkdir -p "$PERSIST_MNT" "$(dirname "$DEPLOY_KEY")" "$CREDS_DIR"

      # Mount persist read-only so we can read keystores and homed records.
      mount -o ro "$PERSIST_DEV" "$PERSIST_MNT"
      trap 'umount "$PERSIST_MNT" 2>/dev/null || true' EXIT

      # Interactive prompts. systemd-ask-password handles the cosmetic UI
      # (plymouth/console/ssh askpw agents all work).
      USERNAME=$(systemd-ask-password --timeout=0 "brdboot user:")
      PASSWORD=$(systemd-ask-password --timeout=0 "Password:")

      KEYSTORE="$PERSIST_MNT/keystores/$USERNAME.keystore"
      if [ ! -f "$KEYSTORE" ]; then
        echo "brdboot: no keystore for user '$USERNAME'" >&2
        exit 1
      fi

      # Open keystore with the user's password. Failure = wrong password.
      MAPPER="brdboot-keystore-$USERNAME"
      echo -n "$PASSWORD" | cryptsetup open --type luks2 --key-file=- \
        "$KEYSTORE" "$MAPPER"

      # The keystore's decrypted volume is a tiny blob containing the
      # deployment key verbatim. Read it out, close the keystore.
      cp "/dev/mapper/$MAPPER" "$DEPLOY_KEY"
      cryptsetup close "$MAPPER"

      # systemd-cryptsetup@brd-system reads its key from this path via the
      # crypttab keyfile parameter (set in the service unit below).
      install -m 0400 "$DEPLOY_KEY" /run/brdboot/deploy.key

      # Stage the credentials for post-boot auto-login. Commit 5 adds a
      # PAM consumer; commit 7d gates the actual staging here.
      install -m 0400 /dev/stdin "$CREDS_DIR/brdboot.login-user" \
        <<< "$USERNAME"
      install -m 0400 /dev/stdin "$CREDS_DIR/brdboot.login-password" \
        <<< "$PASSWORD"
    '';
  };
in
{
  options.brdboot.singlePrompt = {
    enable =
      lib.mkEnableOption "initrd single-prompt auth via per-user keystores";

    systemLuksPartition = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/brd-system";
      description = ''
        The system LUKS device that the keystore-derived deployment key
        unlocks.
      '';
    };

    persistPartition = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/brd-persist";
      description = ''
        The persist partition that holds `/keystores/<user>.keystore`
        files and systemd-homed user records.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Scripts are built as their own derivation so they can be inspected,
    # unit-tested, and referenced by absolute store path from the unit.
    environment.systemPackages = [ unlockScript ];

    boot.initrd.systemd = {
      enable = true;

      # cryptsetup must be available in initrd to open the keystore.
      storePaths = [
        "${pkgs.cryptsetup}/bin/cryptsetup"
        "${unlockScript}/bin/brdboot-unlock"
      ];

      services.brdboot-unlock = {
        description = "brdboot: keystore unlock and credential staging";
        wantedBy = [ "cryptsetup.target" ];
        before = [ "cryptsetup.target" "systemd-cryptsetup@brd\\x2dsystem.service" ];
        requires = [ ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${unlockScript}/bin/brdboot-unlock";
        };
      };
    };
  };
}
