# Initrd-side logic for single-prompt boot authentication.
#
# When enabled, the initrd:
#   1. Mounts brd-persist read-only at /brdboot-persist
#   2. Prompts the user for username and password
#   3. Opens /brdboot-persist/keystores/<username>.keystore with the password,
#      revealing the deployment key that unlocks brd-system
#   4. Stages the deployment key for systemd-cryptsetup@brd-system
#   5. Stages the username and password as systemd credentials for later
#      consumption by a PAM auto-login wrapper (see autoLogin sub-option)
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

  brdbootPamCredential =
    pkgs.callPackage ../../packages/brdboot-pam-credential { };

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
      PERSIST_MNT="/brdboot-persist"
      DEPLOY_KEY="/run/brdboot/deploy.key"
      CREDS_DIR="/run/credentials/@system"

      mkdir -p "$PERSIST_MNT" "$(dirname "$DEPLOY_KEY")" "$CREDS_DIR"

      # Prompt first — credentials are staged regardless of whether
      # a keystore unlock happens. systemd-ask-password handles the
      # cosmetic UI (plymouth/console/ssh askpw agents all work).
      USERNAME=$(systemd-ask-password --timeout=0 "brdboot user:")
      PASSWORD=$(systemd-ask-password --timeout=0 "Password:")

      # Try the keystore unlock flow. If brd-persist isn't available
      # or there's no keystore for this user, fall back to
      # credential-staging only (test mode; variants without LUKS
      # brd-system or without keystore provisioning get the credential
      # passthrough without the unlock step).
      if mount -o ro "$PERSIST_DEV" "$PERSIST_MNT" 2>/dev/null; then
        trap 'umount "$PERSIST_MNT" 2>/dev/null || true' EXIT
        KEYSTORE="$PERSIST_MNT/keystores/$USERNAME.keystore"
        if [ -f "$KEYSTORE" ]; then
          MAPPER="brdboot-keystore-$USERNAME"
          echo -n "$PASSWORD" | cryptsetup open --type luks2 --key-file=- \
            "$KEYSTORE" "$MAPPER"
          # Keystore's decrypted volume is a tiny blob containing the
          # deployment key verbatim. Read it, stage it, close.
          cp "/dev/mapper/$MAPPER" "$DEPLOY_KEY"
          cryptsetup close "$MAPPER"
          install -m 0400 "$DEPLOY_KEY" /run/brdboot/deploy.key
        else
          echo "brdboot-unlock: no keystore for '$USERNAME' — skipping LUKS unlock" >&2
        fi
      else
        echo "brdboot-unlock: $PERSIST_DEV unavailable — skipping LUKS unlock" >&2
      fi

      # Stage credentials unconditionally for post-boot auto-login.
      install -m 0400 /dev/stdin "$CREDS_DIR/brdboot.login-user" \
        <<< "$USERNAME"
      install -m 0400 /dev/stdin "$CREDS_DIR/brdboot.login-password" \
        <<< "$PASSWORD"
    '';
  };

  # agetty wrapper that reads the staged username and execs agetty
  # with --autologin. Falls back to a normal login prompt if no
  # credential is staged (e.g. when booting without the unlock flow).
  autologinGetty = pkgs.writeShellApplication {
    name = "brdboot-autologin-getty";
    runtimeInputs = with pkgs; [ util-linux coreutils ];
    text = ''
      set -eu

      CRED="/run/credentials/@system/brdboot.login-user"
      TTY="$1"

      if [ -f "$CRED" ] && [ -s "$CRED" ]; then
        USERNAME=$(tr -d '\n\r' < "$CRED")
        exec ${pkgs.util-linux}/sbin/agetty \
          --autologin "$USERNAME" --noclear "$TTY" 38400 linux
      else
        exec ${pkgs.util-linux}/sbin/agetty --noclear "$TTY" 38400 linux
      fi
    '';
  };
in
{
  options.brdboot.singlePrompt = {
    enable =
      lib.mkEnableOption "initrd single-prompt auth via per-user keystores";

    autoLogin = lib.mkEnableOption ''
      auto-login on tty1 using credentials staged by the initrd unlock.
      When both this and `enable` are set, pam_brdboot_credential is added
      to the login PAM stack and getty@tty1 is overridden to pass
      --autologin with the staged username
    '';

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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
          before = [
            "cryptsetup.target"
            "systemd-cryptsetup@brd\\x2dsystem.service"
          ];
          requires = [ ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${unlockScript}/bin/brdboot-unlock";
          };
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.autoLogin) {
      # Stack pam_brdboot_credential before pam_unix for login and getty.
      # `sufficient` means: if our module succeeds (credential available,
      # PAM_USER and PAM_AUTHTOK set), skip the rest of the auth chain.
      # When no credential is staged, the module returns PAM_IGNORE and
      # the chain continues normally.
      security.pam.services.login.rules.auth.brdboot-credential = {
        order = 5000; # before pam_unix (~10000)
        control = "sufficient";
        modulePath =
          "${brdbootPamCredential}/lib/security/pam_brdboot_credential.so";
      };

      # Override getty@tty1 to use our autologin wrapper. The wrapper
      # reads the staged credential and invokes agetty --autologin with
      # the correct username.
      systemd.services."getty@tty1".serviceConfig.ExecStart = [
        "" # reset the default
        "${autologinGetty}/bin/brdboot-autologin-getty %I"
      ];

      # Belt-and-suspenders cleanup: the PAM module unlinks the credential
      # files on successful read, but if auto-login never runs (getty
      # crash, user logged in via ssh instead, etc.) the files would
      # linger in /run/credentials/@system/ until reboot. Remove them
      # unconditionally once the system has reached multi-user — PAM has
      # either consumed them by now or never will on this boot.
      systemd.services.brdboot-cred-cleanup = {
        description = "brdboot: remove leftover staged login credentials";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/rm -f"
            + " /run/credentials/@system/brdboot.login-user"
            + " /run/credentials/@system/brdboot.login-password";
        };
      };
    })
  ];
}
