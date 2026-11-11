#include "pam_helper.h"

#include <dlfcn.h>
#include <errno.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>

namespace {

// <security/_pam_types.h>. libpam is dlopened, as it was when the shell
// called it over FFI, so the build needs no libpam headers and a machine
// without libpam still runs the shell. The lock screen then reports PAM as
// unavailable.
constexpr int kPamSuccess = 0;
constexpr int kPamPromptEchoOff = 1;
constexpr int kPamPromptEchoOn = 2;
constexpr int kPamBufErr = 5;
constexpr int kPamConvErr = 19;
constexpr int kPamMaxNumMsg = 32;

struct PamMessage {
  int msg_style;
  const char* msg;
};

struct PamResponse {
  char* resp;
  int resp_retcode;
};

struct PamConv {
  int (*conv)(int, const PamMessage**, PamResponse**, void*);
  void* appdata_ptr;
};

using PamStart = int (*)(const char*, const char*, const PamConv*, void**);
using PamAuthenticate = int (*)(void*, int);
using PamEnd = int (*)(void*, int);

// The longest password read. Anything longer is refused rather than cut short,
// since a truncated password is just a different, wrong one.
constexpr size_t kMaxPassword = 4096;

// Answers every password prompt with the password from stdin. PAM owns the
// array and each string afterwards and free()s them, so both come from malloc.
int converse(int num_msg,
             const PamMessage** msg,
             PamResponse** resp,
             void* appdata) {
  if (num_msg <= 0 || num_msg > kPamMaxNumMsg) return kPamConvErr;
  auto* replies =
      static_cast<PamResponse*>(calloc(num_msg, sizeof(PamResponse)));
  if (replies == nullptr) return kPamBufErr;
  const char* password = static_cast<const char*>(appdata);
  for (int i = 0; i < num_msg; i++) {
    const int style = msg[i]->msg_style;
    if (style != kPamPromptEchoOff && style != kPamPromptEchoOn) continue;
    replies[i].resp = strdup(password);
    if (replies[i].resp == nullptr) {
      for (int j = 0; j < i; j++) free(replies[j].resp);
      free(replies);
      return kPamBufErr;
    }
  }
  *resp = replies;
  return kPamSuccess;
}

// Reads stdin to EOF into buffer as a NUL-terminated string. False when it
// does not fit or cannot be read.
bool read_password(char* buffer, size_t capacity) {
  size_t length = 0;
  while (true) {
    if (length == capacity - 1) {
      // Full: the password fits only if stdin ends exactly here.
      char extra;
      ssize_t more;
      do {
        more = read(STDIN_FILENO, &extra, 1);
      } while (more < 0 && errno == EINTR);
      buffer[length] = '\0';
      return more == 0;
    }
    const ssize_t got =
        read(STDIN_FILENO, buffer + length, capacity - 1 - length);
    if (got < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    if (got == 0) break;
    length += static_cast<size_t>(got);
  }
  buffer[length] = '\0';
  // A NUL inside the input would make PAM check a shorter password than the
  // one typed.
  return strlen(buffer) == length;
}

int authenticate(const char* service, const char* username, char* password) {
  void* lib = dlopen("libpam.so.0", RTLD_NOW | RTLD_LOCAL);
  if (lib == nullptr) lib = dlopen("libpam.so", RTLD_NOW | RTLD_LOCAL);
  if (lib == nullptr) return kPamHelperUnavailable;

  auto pam_start = reinterpret_cast<PamStart>(dlsym(lib, "pam_start"));
  auto pam_authenticate =
      reinterpret_cast<PamAuthenticate>(dlsym(lib, "pam_authenticate"));
  auto pam_end = reinterpret_cast<PamEnd>(dlsym(lib, "pam_end"));
  if (pam_start == nullptr || pam_authenticate == nullptr ||
      pam_end == nullptr) {
    return kPamHelperUnavailable;
  }

  const PamConv conv = {converse, password};
  void* handle = nullptr;
  if (pam_start(service, username, &conv, &handle) != kPamSuccess) {
    return kPamHelperUnavailable;
  }
  const int status = pam_authenticate(handle, 0);
  pam_end(handle, status);
  return status == kPamSuccess ? kPamHelperAccepted : kPamHelperRejected;
}

}  // namespace

int run_pam_helper(int argc, char** argv) {
  if (argc != 4 || argv[2][0] == '\0' || argv[3][0] == '\0') {
    return kPamHelperUnavailable;
  }

  static char password[kMaxPassword + 1];
  if (!read_password(password, sizeof(password))) {
    memset(password, 0, sizeof(password));
    return kPamHelperRejected;
  }
  // Never hand an empty secret to PAM: an account configured with `nullok`
  // would otherwise unlock on a bare Enter press. The shell checks this too.
  if (password[0] == '\0') return kPamHelperRejected;

  const int result = authenticate(argv[2], argv[3], password);
  memset(password, 0, sizeof(password));
  return result;
}
