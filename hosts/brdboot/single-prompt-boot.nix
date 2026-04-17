# Initrd-side logic for single-prompt boot authentication.
#
# Under brdboot.singlePrompt.enable the boot flow is:
#   1. initrd starts; brd-keystores is readable (plaintext partition,
#      contents are LUKS2 blobs), brd-system is LUKS-sealed
#   2. brdboot-unlock prompts the operator for username + password
#   3. The user's keystore on brd-keystores is opened with the
#      password, revealing the shared deployment key for brd-system
#   4. systemd-cryptsetup@brd-system consumes that deployment key and
#      unlocks brd-system
#   5. Username + password are staged under /run/credentials/@system/
#      for the post-pivot PAM stack to consume
#   6. Boot continues: pivot-root, multi-user.target, login
#
# The keystore pattern lets each user have a distinct password that
# indirectly unlocks the shared deployment-keyed system partition.
# Revocation is deleting the user's .keystore file — their password
# no longer opens anything, but the deployment key continues to work
# for other users' keystores.
{ lib, pkgs, config, ... }:
let
  cfg = config.brdboot.singlePrompt;

  # Shell application executed by the brdboot-unlock systemd unit (see
  # `services.brdboot-unlock` below). Runs once per boot, inside the
  # initrd, ordered `before` cryptsetup.target so the deployment key it
  # extracts is in place when systemd-cryptsetup@brd-system activates.
  #
  # Preconditions (must hold when this runs):
  #   - brd-keystores partition is reachable (systemd dev-*.device
  #     ordering makes the node available; this script handles the
  #     mount itself)
  #   - cryptsetup + util-linux + coreutils are in the initrd (ensured
  #     via boot.initrd.systemd.storePaths in `config` below)
  #   - a systemd-ask-password agent is live (plymouth/console/ssh) so
  #     the prompts can reach an operator
  #
  # Runtime sequence:
  #   1. Mount brd-keystores read-only at /brdboot-keystores
  #   2. Prompt for username, then password (both via
  #      systemd-ask-password so any registered agent can answer)
  #   3. Open /brdboot-keystores/<username>.keystore with the
  #      password — failure means wrong password, boot halts
  #   4. Copy the decrypted keystore's contents (the deployment key)
  #      to /run/brdboot/deploy.key and close the keystore mapper
  #   5. Install the deploy key at the path
  #      systemd-cryptsetup@brd-system reads via its crypttab entry
  #   6. Stage username + password as systemd credentials under
  #      /run/credentials/@system/ for a later PAM consumer to pick up
  #
  # Unmounting brd-keystores happens in the script's EXIT trap.
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

      KEYSTORES_DEV="${cfg.keystorePartition}"
      SYSTEM_DEV="${cfg.systemLuksPartition}"
      KEYSTORES_MNT="/brdboot-keystores"
      DEPLOY_KEY="/run/brdboot/deploy.key"
      CREDS_DIR="/run/credentials/@system"

      mkdir -p "$KEYSTORES_MNT" "$(dirname "$DEPLOY_KEY")" "$CREDS_DIR"

      # Mount keystores partition read-only for the keystore lookup.
      mount -o ro "$KEYSTORES_DEV" "$KEYSTORES_MNT"
      trap 'umount "$KEYSTORES_MNT" 2>/dev/null || true' EXIT

      # Interactive prompts. systemd-ask-password handles the cosmetic UI
      # (plymouth/console/ssh askpw agents all work).
      USERNAME=$(systemd-ask-password --timeout=0 "brdboot user:")
      PASSWORD=$(systemd-ask-password --timeout=0 "Password:")

      KEYSTORE="$KEYSTORES_MNT/$USERNAME.keystore"
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

      # Stage the credentials for post-boot auto-login. A PAM consumer
      # in the booted system reads them from /run/credentials/@system/
      # to complete login without a second password prompt.
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

    keystorePartition = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/brd-keystores";
      description = ''
        Partition that holds per-user `<user>.keystore` LUKS2 blobs.
        Mounted read-only in the initrd; each file is opened with the
        user's password to reveal the deployment key for brd-system.
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
