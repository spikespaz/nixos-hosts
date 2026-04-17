/*
 * pam_brdboot_credential.so — PAM auto-login from systemd credentials
 *
 * Reads /run/credentials/@system/brdboot.login-{user,password} (staged
 * by the initrd's brdboot-unlock service after keystore authentication)
 * and sets PAM_USER + PAM_AUTHTOK. Subsequent modules in the PAM stack
 * (pam_systemd_home, etc.) consume these to complete login without a
 * second password prompt.
 *
 * Intended to be stacked as `sufficient` before pam_unix so that it
 * provides the credentials when present but falls through otherwise.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#define PAM_SM_AUTH
#include <security/pam_ext.h>
#include <security/pam_modules.h>

#define CREDS_DIR "/run/credentials/@system"
#define USER_FILE CREDS_DIR "/brdboot.login-user"
#define PASS_FILE CREDS_DIR "/brdboot.login-password"
#define MAX_LEN 256

static int read_cred(const char *path, char *buf, size_t buflen) {
  int fd = open(path, O_RDONLY | O_NOFOLLOW);
  if (fd < 0) {
    return -1;
  }
  ssize_t n = read(fd, buf, buflen - 1);
  int saved_errno = errno;
  close(fd);
  if (n < 0) {
    errno = saved_errno;
    return -1;
  }
  buf[n] = '\0';
  /* Trim trailing newline if the credential was staged with one. */
  while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
    buf[--n] = '\0';
  }
  return 0;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc,
                                   const char **argv) {
  (void)flags;
  (void)argc;
  (void)argv;

  char user[MAX_LEN];
  char pass[MAX_LEN];
  int rc = PAM_AUTH_ERR;

  if (read_cred(USER_FILE, user, sizeof(user)) != 0) {
    /* No credential staged — this session isn't eligible for auto-login.
     * Return IGNORE so the next module in the stack runs normally. */
    return PAM_IGNORE;
  }
  if (read_cred(PASS_FILE, pass, sizeof(pass)) != 0) {
    pam_syslog(pamh, LOG_WARNING,
               "brdboot-credential: user file present but password missing");
    goto cleanup;
  }

  if (pam_set_item(pamh, PAM_USER, user) != PAM_SUCCESS) {
    pam_syslog(pamh, LOG_ERR, "brdboot-credential: pam_set_item(PAM_USER) failed");
    goto cleanup;
  }
  if (pam_set_item(pamh, PAM_AUTHTOK, pass) != PAM_SUCCESS) {
    pam_syslog(pamh, LOG_ERR, "brdboot-credential: pam_set_item(PAM_AUTHTOK) failed");
    goto cleanup;
  }

  rc = PAM_SUCCESS;

cleanup:
  /* Wipe the local copies of credentials — PAM has its own handles now. */
  explicit_bzero(pass, sizeof(pass));
  explicit_bzero(user, sizeof(user));
  return rc;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc,
                              const char **argv) {
  (void)pamh;
  (void)flags;
  (void)argc;
  (void)argv;
  return PAM_SUCCESS;
}
