// The verbs of the desktop grid: opening an item, listing what else could open
// it, and deciding what it is called and which icon it wears.
//
// Flutter-free on purpose, so the GIO lifetimes are reviewable in one place
// without any widget noise around them.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/config.dart';

/// The last path segment of [path], tolerant of a trailing slash.
///
/// Deliberately not `basenameOf` from `overlay/file_picker.dart`: that lives in
/// a Flutter file, and importing it would drag widgets into this layer.
String desktopBasename(String path) {
  var trimmed = path;
  while (trimmed.length > 1 && trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final slash = trimmed.lastIndexOf('/');
  if (slash < 0) return trimmed;
  if (slash == 0 && trimmed.length == 1) return trimmed;
  return trimmed.substring(slash + 1);
}

/// What an item is called when the user has not renamed it: the desktop entry's
/// own name for an application, the basename otherwise.
///
/// [resolved] is the already-loaded entry for an app item, so callers that keep
/// one around do not pay for a second GIO lookup here.
String labelForItem(DesktopItem item, {AppEntry? resolved}) {
  final override = item.label;
  if (override != null && override.trim().isNotEmpty) return override.trim();

  if (item.kind == DesktopItemKind.app) {
    final name = resolved?.name;
    if (name != null && name.isNotEmpty) return name;
    // No entry: fall back to the filename minus `.desktop`, which is at least
    // recognisable, rather than showing nothing.
    final base = desktopBasename(item.target);
    return base.toLowerCase().endsWith('.desktop')
        ? base.substring(0, base.length - '.desktop'.length)
        : base;
  }
  return desktopBasename(item.target);
}

/// The themed icon name for [item], or empty when there is nothing to suggest
/// and the caller should draw its own fallback glyph.
String iconNameForItem(DesktopItem item, {AppEntry? resolved}) {
  switch (item.kind) {
    case DesktopItemKind.app:
      return resolved?.iconName ?? '';
    case DesktopItemKind.folder:
      return 'folder';
    case DesktopItemKind.file:
      return iconNameForPath(item.target, isDirectory: false);
  }
}

/// Whether [item] still points at something that exists.
///
/// A pinned item whose target has been deleted is shown dimmed rather than
/// removed: silently dropping an icon because a network mount was offline would
/// lose the user's arrangement.
bool desktopItemExists(DesktopItem item) {
  if (item.kind == DesktopItemKind.folder) {
    return Directory(item.target).existsSync();
  }
  return File(item.target).existsSync();
}

/// Opens [item] the way a double-click should.
///
/// An application is launched; a file or folder goes to its default handler,
/// which for a directory is the file manager. Returns false when the target is
/// gone or GIO refused, so the caller can leave the icon selected rather than
/// pretending something happened.
bool openDesktopItem(DesktopItem item) {
  if (item.kind == DesktopItemKind.app) {
    final entry = loadAppByPath(item.target);
    if (entry == null) return false;
    try {
      launchApp(entry.appInfo);
      return true;
    } finally {
      // Resolved fresh for this launch and unref'd immediately: nothing here
      // outlives the call, so there is no pointer to invalidate later.
      disposeAppEntries([entry]);
    }
  }
  if (!desktopItemExists(item)) return false;
  return openPathWithDefault(item.target);
}

/// The applications offered by "Open with…", best first.
///
/// **The caller owns every entry's `GAppInfo*`** and must pass the list to
/// [disposeAppEntries] when the menu closes — see `appsForPath`, which explains
/// why this cannot come from `AppIndex`.
List<AppEntry> openWithCandidates(DesktopItem item) {
  if (item.kind == DesktopItemKind.app) return const [];
  return appsForPath(
    item.target,
    isDirectory: item.kind == DesktopItemKind.folder,
  );
}

/// Opens [item] with a specific [handler] from [openWithCandidates].
void openDesktopItemWith(DesktopItem item, AppEntry handler) =>
    openDesktopItemWithPointer(item, handler.appInfo);

/// The pointer-level form, for callers holding a `GAppInfo*` directly.
void openDesktopItemWithPointer(
  DesktopItem item,
  ffi.Pointer<ffi.NativeType> appInfo,
) {
  launchAppWithPath(appInfo, item.target);
}

/// Builds the item a newly-picked [path] should become, inferring its kind.
DesktopItem desktopItemForPath(String path) => DesktopItem(
      kind: inferDesktopItemKind(path),
      target: path,
    );
