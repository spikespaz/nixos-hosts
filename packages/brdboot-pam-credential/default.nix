# Custom PAM module that reads systemd-staged credentials
# (/run/credentials/@system/brdboot.login-{user,password}) and sets
# PAM_USER + PAM_AUTHTOK so downstream stack modules (pam_systemd_home
# in particular) can complete login without a second password prompt.
#
# Wired into the PAM stack by single-prompt-boot.nix when
# brdboot.singlePrompt.autoLogin is enabled.
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
