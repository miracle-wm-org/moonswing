// Shared GIO application-info layer.
//
// Wraps GLib's `GAppInfo` / `GDesktopAppInfo` over FFI so both the dock
// ([modules/dock.dart], which resolves a fixed set of pinned ids) and the app
// directory ([modules/app_directory.dart], which enumerates every installed
// app) go through one implementation. Also provides [AppIconImage], the shared
// icon-rendering widget, so pinned icons and directory icons look identical.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:xdg_icons/xdg_icons.dart';

// ---------------------------------------------------------------------------
// GIO / GLib FFI bindings
// ---------------------------------------------------------------------------

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Int)>(symbol: 'g_malloc0')
external ffi.Pointer<ffi.NativeType> _gMalloc0(int count);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(symbol: 'g_free')
external void _gFree(ffi.Pointer<ffi.NativeType> value);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_object_unref')
external void _gObjectUnref(ffi.Pointer<ffi.NativeType> object);

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.Uint8>)>(
    symbol: 'g_desktop_app_info_new')
external ffi.Pointer<ffi.NativeType> _gDesktopAppInfoNew(
    ffi.Pointer<ffi.Uint8> desktopId);

/// Returns a freshly-allocated `GList*` of `GAppInfo*` for every registered
/// application. The list is owned by the caller: unref each element and free
/// the list.
@ffi.Native<ffi.Pointer<_GList> Function()>(symbol: 'g_app_info_get_all')
external ffi.Pointer<_GList> _gAppInfoGetAll();

@ffi.Native<ffi.Void Function(ffi.Pointer<_GList>)>(symbol: 'g_list_free')
external void _gListFree(ffi.Pointer<_GList> list);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_should_show')
external int _gAppInfoShouldShow(ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_get_id')
external ffi.Pointer<ffi.Uint8> _gAppInfoGetId(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_get_name')
external ffi.Pointer<ffi.Uint8> _gAppInfoGetName(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_app_info_get_icon')
external ffi.Pointer<ffi.NativeType> _gAppInfoGetIcon(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_icon_to_string')
external ffi.Pointer<ffi.Uint8> _gIconToString(
    ffi.Pointer<ffi.NativeType> icon);

/// `GDesktopAppInfo*` — returns the raw `Categories=` string (semicolon
/// separated), or NULL. The pointer from [_gAppInfoGetAll] is a
/// `GDesktopAppInfo` instance, so it can be passed directly.
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_desktop_app_info_get_categories')
external ffi.Pointer<ffi.Uint8> _gDesktopAppInfoGetCategories(
    ffi.Pointer<ffi.NativeType> appInfo);

@ffi.Native<
    ffi.Int Function(
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.NativeType>)>(symbol: 'g_app_info_launch')
external int _gAppInfoLaunch(
    ffi.Pointer<ffi.NativeType> appInfo,
    ffi.Pointer<ffi.NativeType> files,
    ffi.Pointer<ffi.NativeType> context,
    ffi.Pointer<ffi.NativeType> error);

/// `GDesktopAppInfo*` — the ids of the entry's `[Desktop Action …]` groups, as
/// a NULL-terminated `gchar**`. Owned by the appinfo: read it, never free it.
@ffi.Native<ffi.Pointer<ffi.Pointer<ffi.Uint8>> Function(
    ffi.Pointer<ffi.NativeType>)>(symbol: 'g_desktop_app_info_list_actions')
external ffi.Pointer<ffi.Pointer<ffi.Uint8>> _gDesktopAppInfoListActions(
    ffi.Pointer<ffi.NativeType> appInfo);

/// The localised display name of one action id. Caller frees the result.
@ffi.Native<
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.Uint8>)>(symbol: 'g_desktop_app_info_get_action_name')
external ffi.Pointer<ffi.Uint8> _gDesktopAppInfoGetActionName(
    ffi.Pointer<ffi.NativeType> appInfo, ffi.Pointer<ffi.Uint8> action);

/// Launches one action by *id* (not by display name). Returns void — unlike
/// `g_app_info_launch` there is no GError to inspect.
@ffi.Native<
    ffi.Void Function(
        ffi.Pointer<ffi.NativeType>,
        ffi.Pointer<ffi.Uint8>,
        ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_desktop_app_info_launch_action')
external void _gDesktopAppInfoLaunchAction(
    ffi.Pointer<ffi.NativeType> appInfo,
    ffi.Pointer<ffi.Uint8> action,
    ffi.Pointer<ffi.NativeType> launchContext);

/// `Keywords=` from the desktop entry, NULL-terminated and owned by the
/// appinfo. What makes searching "browser" find Firefox.
@ffi.Native<ffi.Pointer<ffi.Pointer<ffi.Uint8>> Function(
    ffi.Pointer<ffi.NativeType>)>(symbol: 'g_desktop_app_info_get_keywords')
external ffi.Pointer<ffi.Pointer<ffi.Uint8>> _gDesktopAppInfoGetKeywords(
    ffi.Pointer<ffi.NativeType> appInfo);

/// `GenericName=` — "Web Browser" for Firefox. May be NULL; owned by the
/// appinfo.
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'g_desktop_app_info_get_generic_name')
external ffi.Pointer<ffi.Uint8> _gDesktopAppInfoGetGenericName(
    ffi.Pointer<ffi.NativeType> appInfo);

/// A `GdkAppLaunchContext*` for the default display, or NULL. Passing one to
/// `g_app_info_launch` gives the launched app a startup-notification token, so
/// it wins the focus race against the overlay closing behind it.
@ffi.Native<ffi.Pointer<ffi.NativeType> Function(ffi.Pointer<ffi.NativeType>)>(
    symbol: 'gdk_display_get_app_launch_context')
external ffi.Pointer<ffi.NativeType> _gdkDisplayGetAppLaunchContext(
    ffi.Pointer<ffi.NativeType> display);

@ffi.Native<ffi.Pointer<ffi.NativeType> Function()>(
    symbol: 'gdk_display_get_default')
external ffi.Pointer<ffi.NativeType> _gdkDisplayGetDefault();

/// Minimal view of GLib's `GList` node: a data pointer and a forward link.
final class _GList extends ffi.Struct {
  external ffi.Pointer<ffi.NativeType> data;
  external ffi.Pointer<_GList> next;
  external ffi.Pointer<_GList> prev;
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

ffi.Pointer<ffi.Uint8> _stringToNative(String value) {
  final Uint8List units = utf8.encode(value);
  final ffi.Pointer<ffi.Uint8> buffer =
      _gMalloc0(units.length + 1).cast<ffi.Uint8>();
  final Uint8List nativeString = buffer.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return buffer;
}

String _nativeToString(ffi.Pointer<ffi.Uint8> value) {
  var length = 0;
  while (value[length] != 0) {
    length++;
  }
  return utf8.decode(value.asTypedList(length));
}

/// Copies a NULL-terminated `gchar**` into Dart strings. Every `strv` this file
/// reads is transfer-none, so nothing here is freed.
List<String> _strvToList(ffi.Pointer<ffi.Pointer<ffi.Uint8>> strv) {
  if (strv == ffi.nullptr) return const [];
  final values = <String>[];
  for (var i = 0; strv[i] != ffi.nullptr; i++) {
    values.add(_nativeToString(strv[i]));
  }
  return values;
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// One of an application's alternative launch options — a `[Desktop Action …]`
/// group, e.g. Firefox's "New Private Window".
class AppAction {
  /// The action id, which is what [launchAppAction] takes. Not the label.
  final String id;

  /// The localised label to show the user.
  final String name;

  const AppAction({required this.id, required this.name});
}

/// A resolved installed application. [appInfo] is a live `GAppInfo*` retained
/// for launching; callers that build [AppEntry]s must unref it when done.
class AppEntry {
  /// The config id (desktop-file basename without the `.desktop` suffix), e.g.
  /// `firefox_firefox`. This is the value stored in `[modules.dock].apps`.
  final String id;
  final String name;
  final String iconName;

  /// Raw freedesktop `Categories=` values (e.g. `['Network', 'WebBrowser']`).
  final List<String> categories;

  /// `GenericName=` — "Web Browser" — or empty.
  final String genericName;

  /// `Keywords=` — extra search terms the entry declares.
  final List<String> keywords;

  /// Alternative launch options, empty for most applications.
  final List<AppAction> actions;

  final ffi.Pointer<ffi.NativeType> appInfo;

  const AppEntry({
    required this.id,
    required this.name,
    required this.iconName,
    required this.categories,
    required this.appInfo,
    this.genericName = '',
    this.keywords = const [],
    this.actions = const [],
  });
}

/// Resolves a single pinned desktop id (as stored in `[modules.dock].apps`) to
/// an [AppEntry], or null if no matching `.desktop` file exists. The returned
/// entry's [appInfo] must be unref'd by the caller (see [disposeAppEntries]).
AppEntry? loadAppById(String id) {
  final desktopId = _stringToNative('$id.desktop');
  try {
    final appInfo = _gDesktopAppInfoNew(desktopId);
    if (appInfo == ffi.nullptr) return null;
    return _entryFromAppInfo(appInfo, fallbackId: id);
  } finally {
    _gFree(desktopId.cast());
  }
}

/// Enumerates every installed application that should be shown in menus,
/// sorted case-insensitively by display name. Each entry's [appInfo] must be
/// unref'd by the caller (see [disposeAppEntries]).
List<AppEntry> loadInstalledApps() {
  final entries = <AppEntry>[];
  final head = _gAppInfoGetAll();
  var node = head;
  while (node != ffi.nullptr) {
    final ref = node.ref;
    final appInfo = ref.data;
    node = ref.next;
    if (appInfo == ffi.nullptr) continue;
    if (_gAppInfoShouldShow(appInfo) == 0) {
      _gObjectUnref(appInfo);
      continue;
    }
    entries.add(_entryFromAppInfo(appInfo, fallbackId: ''));
  }
  if (head != ffi.nullptr) _gListFree(head);
  entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return entries;
}

AppEntry _entryFromAppInfo(
  ffi.Pointer<ffi.NativeType> appInfo, {
  required String fallbackId,
}) {
  // Id: strip the trailing ".desktop" so it matches the config format.
  var id = fallbackId;
  final idPtr = _gAppInfoGetId(appInfo);
  if (idPtr != ffi.nullptr) {
    final raw = _nativeToString(idPtr);
    id = raw.endsWith('.desktop')
        ? raw.substring(0, raw.length - '.desktop'.length)
        : raw;
  }

  final namePtr = _gAppInfoGetName(appInfo);
  final name =
      namePtr != ffi.nullptr ? _nativeToString(namePtr) : (id.isEmpty ? '?' : id);

  var iconName = id;
  final iconPtr = _gAppInfoGetIcon(appInfo);
  if (iconPtr != ffi.nullptr) {
    final iconStr = _gIconToString(iconPtr);
    if (iconStr != ffi.nullptr) {
      iconName = _nativeToString(iconStr);
      _gFree(iconStr.cast());
    }
  }

  final categories = <String>[];
  final catPtr = _gDesktopAppInfoGetCategories(appInfo);
  if (catPtr != ffi.nullptr) {
    for (final c in _nativeToString(catPtr).split(';')) {
      final t = c.trim();
      if (t.isNotEmpty) categories.add(t);
    }
  }

  final genericPtr = _gDesktopAppInfoGetGenericName(appInfo);
  final genericName =
      genericPtr != ffi.nullptr ? _nativeToString(genericPtr) : '';

  final actions = <AppAction>[];
  for (final actionId in _strvToList(_gDesktopAppInfoListActions(appInfo))) {
    final namePtr = _stringToNative(actionId);
    try {
      final labelPtr = _gDesktopAppInfoGetActionName(appInfo, namePtr);
      if (labelPtr == ffi.nullptr) continue;
      actions.add(AppAction(id: actionId, name: _nativeToString(labelPtr)));
      _gFree(labelPtr.cast());
    } finally {
      _gFree(namePtr.cast());
    }
  }

  return AppEntry(
    id: id,
    name: name,
    iconName: iconName,
    categories: categories,
    genericName: genericName,
    keywords: _strvToList(_gDesktopAppInfoGetKeywords(appInfo)),
    actions: actions,
    appInfo: appInfo,
  );
}

/// Unrefs every entry's retained `GAppInfo*`. Call from `dispose`.
void disposeAppEntries(Iterable<AppEntry> entries) {
  for (final e in entries) {
    _gObjectUnref(e.appInfo);
  }
}

/// A `GdkAppLaunchContext*` for the default display, or NULL if there isn't
/// one. The caller owns it and must unref it.
///
/// Worth the extra call: without a launch context the launched application has
/// no startup-notification token, and a shell surface closing in the same frame
/// can win the focus race against it.
ffi.Pointer<ffi.NativeType> _launchContext() {
  try {
    final display = _gdkDisplayGetDefault();
    if (display == ffi.nullptr) return ffi.nullptr;
    return _gdkDisplayGetAppLaunchContext(display);
  } catch (_) {
    return ffi.nullptr;
  }
}

/// Launches [appInfo] (a `GAppInfo*`), swallowing any error.
void launchApp(ffi.Pointer<ffi.NativeType> appInfo) {
  final context = _launchContext();
  try {
    _gAppInfoLaunch(appInfo, ffi.nullptr, context, ffi.nullptr);
  } catch (_) {
    // Launch failed — nothing useful to surface from here.
  } finally {
    if (context != ffi.nullptr) _gObjectUnref(context);
  }
}

/// Launches one of [appInfo]'s alternative launch options by [actionId] (an
/// [AppAction.id], not its label), swallowing any error.
void launchAppAction(
    ffi.Pointer<ffi.NativeType> appInfo, String actionId) {
  final action = _stringToNative(actionId);
  final context = _launchContext();
  try {
    _gDesktopAppInfoLaunchAction(appInfo, action, context);
  } catch (_) {
    // Same posture as launchApp: there is nothing useful to report.
  } finally {
    if (context != ffi.nullptr) _gObjectUnref(context);
    _gFree(action.cast());
  }
}

// ---------------------------------------------------------------------------
// Categorisation
// ---------------------------------------------------------------------------

/// Display buckets in priority order: an app is filed under the first bucket
/// whose freedesktop main-category it declares. Apps with no known category
/// land in [kOtherCategory].
const String kOtherCategory = 'Other';

const List<(String, List<String>)> _categoryBuckets = [
  ('Development', ['Development']),
  ('Games', ['Game']),
  ('Graphics', ['Graphics']),
  ('Internet', ['Network']),
  ('Multimedia', ['AudioVideo', 'Audio', 'Video']),
  ('Office', ['Office']),
  ('Education', ['Education', 'Science']),
  ('System', ['System', 'Settings']),
  ('Utilities', ['Utility']),
];

/// The display category [entry] belongs to (one of [_categoryBuckets]' labels
/// or [kOtherCategory]).
String mainCategoryOf(AppEntry entry) {
  final set = entry.categories.toSet();
  for (final (label, keys) in _categoryBuckets) {
    if (keys.any(set.contains)) return label;
  }
  return kOtherCategory;
}

// ---------------------------------------------------------------------------
// Shared icon widget
// ---------------------------------------------------------------------------

/// Renders an application icon by its GIO icon name: an absolute path is drawn
/// with [Image.file], a themed name with [XdgIcon], and anything unresolved
/// falls back to the app's first letter.
class AppIconImage extends StatelessWidget {
  const AppIconImage({
    super.key,
    required this.iconName,
    required this.name,
    required this.size,
    required this.foreground,
  });

  final String iconName;
  final String name;
  final int size;
  final Color foreground;

  Widget _fallback() {
    return SizedBox(
      width: size.toDouble(),
      height: size.toDouble(),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(fontSize: size * 0.6, color: foreground),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (iconName.startsWith('/')) {
      return Image.file(
        File(iconName),
        width: size.toDouble(),
        height: size.toDouble(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return XdgIcon(
      name: iconName,
      size: size,
      iconNotFoundBuilder: _fallback,
    );
  }
}
