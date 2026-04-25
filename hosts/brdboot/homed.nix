# Shared module that conditionally enables systemd-homed.
#
# systemd-homed stores each user's home directory as a LUKS-encrypted
# container, unlocked at login with the user's password. PAM integration
# (pam_systemd_home) is wired automatically by NixOS when the service is
# enabled.
#
# Users created at provisioning time get auditable, individually-encrypted
# homes; revocation is removing the user's homed record.
{ lib, config, ... }:
let
  cfg = config.brdboot.homed;
in
{
  options.brdboot.homed = {
    # Enabled by default so a fresh flashed drive offers account creation
    # on first boot — convenient for testing and ad-hoc deployments. Real
    # deployments that pre-provision accounts (or use a different user
    # model entirely) can set this to false.
    enable = (lib.mkEnableOption "per-user encrypted homes via systemd-homed")
      // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    # Silence the high-system-UID warning about the nixbld build users.
    # Side effect: systemd-homed-firstboot.service may not actually prompt
    # because systemd-userdb sees nixbld* as regular users (UID >=1000).
    # For a proper fix we'd need to lower ids.uids.nixbld or disable the
    # build users entirely — deferred to a follow-up. Until then, create
    # accounts manually after boot: `sudo homectl create <username>`.
    services.userdbd.silenceHighSystemUsers = true;

    services.homed = {
      enable = true;
      # Prompt on first boot so an operator / debugger can spin up an
      # interactive test account without pre-provisioning. Downstream
      # deployments that pre-provision homed records can simply assign
      # `services.homed.promptOnFirstBoot = false;` at regular priority.
      promptOnFirstBoot = lib.mkDefault true;
      settings.Home = {
        # LUKS containers are the only storage class that gives per-user
        # encryption at rest with a password-derived key.
        DefaultStorage = "luks";
        # btrfs supports snapshots and resizing, useful for a recovery
        # context where home content may need rollback.
        DefaultFileSystemType = "btrfs";
      };
    };
  };
}
