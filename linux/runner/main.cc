// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <cstring>

#include "my_application.h"

// snapd installs every snap's desktop entries under
// /var/lib/snapd/desktop/applications and its themed icons (`Icon=snap.<name>.…`)
// under /var/lib/snapd/desktop/icons, and relies on the session putting
// /var/lib/snapd/desktop on XDG_DATA_DIRS — /etc/profile.d does, for a login
// shell, and snapd's systemd environment generator does, for the user manager.
// A compositor started any other way hands the shell neither, and then GIO
// lists no snap at all and GtkIconTheme finds none of their icons. Both read
// XDG_DATA_DIRS once, on first use, so it is put right here, before GTK starts.
static void ensure_snapd_data_dir() {
  static const gchar kSnapdDataDir[] = "/var/lib/snapd/desktop";
  if (!g_file_test(kSnapdDataDir, G_FILE_TEST_IS_DIR)) return;

  const gchar* current = g_getenv("XDG_DATA_DIRS");
  // Unset or empty means the spec's default, which must be kept, not replaced.
  const gchar* dirs =
      current != nullptr && *current != '\0' ? current : "/usr/local/share:/usr/share";
  g_auto(GStrv) parts = g_strsplit(dirs, ":", -1);
  for (gchar** part = parts; *part != nullptr; part++) {
    g_autofree gchar* trimmed = g_strdup(*part);
    gsize length = strlen(trimmed);
    while (length > 1 && trimmed[length - 1] == '/') trimmed[--length] = '\0';
    if (g_strcmp0(trimmed, kSnapdDataDir) == 0) return;
  }
  g_autofree gchar* joined = g_strconcat(dirs, ":", kSnapdDataDir, nullptr);
  g_setenv("XDG_DATA_DIRS", joined, TRUE);
}

int main(int argc, char** argv) {
  ensure_snapd_data_dir();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
