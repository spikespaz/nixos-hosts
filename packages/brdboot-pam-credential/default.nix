# brdboot-pam-credential — PAM auto-login from initrd-staged credentials.
#
# Role in the boot chain:
#
#   initrd: brdboot-unlock (see hosts/brdboot/single-prompt-boot.nix)
#     stages /run/credentials/@system/brdboot.login-{user,password}
#     after the keystore exchange.
#   └─ pivot-root
#      └─ multi-user.target
#         └─ login / getty
#            └─ PAM stack (this module is stacked first, as 'sufficient'):
#               1. Reads the two staged files, sets PAM_USER and
#                  PAM_AUTHTOK on the PAM handle, unlinks the files, and
#                  returns PAM_SUCCESS. The 'sufficient' disposition
#                  short-circuits pam_unix so no interactive password
#                  prompt appears.
#               2. If the credential files are absent (boot with
#                  singlePrompt disabled, or credentials already consumed
#                  in a re-auth), returns PAM_IGNORE and the stack falls
#                  through to pam_unix for a normal interactive prompt.
#               3. Downstream modules (pam_systemd_home in particular)
#                  read PAM_AUTHTOK to unlock the user's LUKS home
#                  container using the same password the operator typed
#                  at the initrd prompt.
#
# The C source at pam_brdboot_credential.c implements pam_sm_authenticate
# and pam_sm_setcred. This derivation compiles it to a dynamically-
# loaded PAM module at $out/lib/security/pam_brdboot_credential.so.
#
# Wired into the PAM stack by hosts/brdboot/single-prompt-boot.nix.
{ stdenv, pam }:
stdenv.mkDerivation {
  pname = "brdboot-pam-credential";
  version = "0.1.0";

  src = ./.;

  buildInputs = [ pam ];

  buildPhase = ''
    runHook preBuild
    $CC -Wall -Wextra -Werror -fPIC -shared \
        -o pam_brdboot_credential.so \
        pam_brdboot_credential.c \
        -lpam
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0755 pam_brdboot_credential.so \
      $out/lib/security/pam_brdboot_credential.so
    runHook postInstall
  '';

  meta = {
    description = "PAM auto-login from brdboot initrd-staged credentials";
  };
}
