# Per-user keystore and homed-record scaffolding.
#
# When enabled, this module generates a derivation that produces the
# directory layouts expected by:
#   - single-prompt-boot.nix (reads <user>.keystore from brd-keystores)
#   - systemd-homed (reads <user>.identity from brd-persist)
#
# Must be imported INSIDE a variant's deferred module (image.modules.<name>)
# because it sets image.repart options which don't exist at the top level.
#
# Keystores go to brd-keystores.contents (dedicated plaintext partition
# for <user>.keystore LUKS2 blobs). Homed identity records stay on
# brd-persist with the rest of the mutable system state.
#
# ## Keystore contents at build time
#
# The keystore files are PLACEHOLDERS — empty LUKS-container stubs with a
# manifest describing the required provisioning. Real keystores are
# generated during provisioning (see README: sealed provisioning), when
# the operator:
#   1. Holds the deployment key
#   2. Assigns per-user passwords
#   3. Runs `cryptsetup luksFormat <placeholder> --key-file=<user-pw>`
#      and writes the deployment key into the decrypted volume
#
# Build time cannot create real LUKS containers reliably — the nix build
# sandbox lacks kernel dm-crypt access unless specially configured, and
# re-keying at provisioning would re-do most of the work anyway.
#
# homed identity records ARE plaintext JSON, so we write those at build
# time from the user list.
{ lib, pkgs, config, ... }:
let
  cfg = config.brdboot.keystores;

  # Build a minimal homed JSON identity record. Real homed records have
  # many fields; the essentials for pre-provisioned accounts are:
  #   - userName
  #   - memberOf (group membership; "users" gets a normal user)
  #   - storage = "luks" (home stored as a LUKS container)
  # Operators can extend records with `homectl update` during provisioning.
  mkHomedRecord = user: builtins.toJSON {
    userName = user.username;
    memberOf = [ "users" ];
    storage = "luks";
    # Real uid/gid are assigned by homed at first `homectl create`.
    # This stub record is just a seed.
  };

  # Derivation that lays out /keystores and /homed directories for
  # inclusion in the image. The two subtrees are routed to different
  # partitions in the config block below. Pure nix (no crypto ops),
  # portable to any sandbox.
  scaffolding = pkgs.runCommand "brdboot-keystores-scaffolding" { } ''
    mkdir -p $out/keystores $out/homed

    # Instructions for the provisioning operator. This file ships in the
    # image so field operators know how to turn placeholders into real
    # keystores without needing the source tree.
    cat > $out/keystores/README <<'END'
    brdboot keystore placeholders.

    Each <username>.keystore file here is an empty placeholder.
    During provisioning, replace each with a real LUKS2 container
    encrypting the deployment key, with the user's password as the
    keyslot passphrase. See /etc/brdboot/provisioning.md on the
    booted system, or the upstream README, for the exact procedure.
    END

    ${lib.concatMapStringsSep "\n" (user: ''
      # Empty placeholder — real LUKS container created at provisioning.
      touch $out/keystores/${user.username}.keystore

      # Plaintext homed identity record — pre-populated at build time.
      cat > $out/homed/${user.username}.identity <<'END'
    ${mkHomedRecord user}
    END
    '') cfg.users}
  '';
in
{
  options.brdboot.keystores = {
    enable = lib.mkEnableOption ''
      per-user keystore and homed record scaffolding on brd-persist.
      Populates the partition's /keystores and /homed directories from
      the users list. Real LUKS keystores are generated at provisioning
    '';

    users = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username = lib.mkOption {
            type = lib.types.str;
            description = "Login username. Must be a valid Unix name.";
          };
        };
      });
      default = [ ];
      example = [
        { username = "user0"; }
        { username = "user1"; }
      ];
      description = ''
        List of accounts to pre-seed on the drive. Each account gets a
        placeholder keystore (filled at provisioning) and a seed homed
        identity record. Default is an empty list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Route the scaffolding output to two partitions:
    #   - keystore LUKS blobs land on brd-keystores (dedicated plaintext
    #     keystore partition). The scaffolding produces $out/keystores/
    #     with one .keystore file per user; repart flattens that onto
    #     the partition root at mount time.
    #   - plaintext homed identity records stay on brd-persist alongside
    #     other mutable system state.
    # repart's contents map merges with other contents entries for the
    # same partition.
    image.repart.partitions."brd-keystores".contents."/".source =
      "${scaffolding}/keystores";
    image.repart.partitions."brd-persist".contents."/homed".source =
      "${scaffolding}/homed";
  };
}
