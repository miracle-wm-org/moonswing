// Default applications, read and written through GIO.
//
// The XDG MIME Applications specification is the one place every desktop, every
// toolkit and `xdg-open` agree to look for "which application opens this":
// `$XDG_CONFIG_HOME/mimeapps.list`, layered over the desktop-specific and system
// copies. GIO is its reference implementation and is already mapped into this
// process — GTK links it, and `lib/app_info.dart` launches everything through
// it — so the pane is a thin view over `g_app_info_get_default_for_type`,
// `g_app_info_set_as_default_for_type` and `g_app_info_reset_type_associations`
// rather than a second parser and writer of somebody else's file.
//
// Widget-free, so a widget test swaps [DefaultAppAssociations] for a fake and
// never touches the user's real associations.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:moonswing/default_apps/default_app_model.dart';

// ---------------------------------------------------------------------------
// GIO / GLib FFI bindings
// ---------------------------------------------------------------------------

/// Minimal view of GLib's `GList` node.
final class _GList extends ffi.Struct {
  external ffi.Pointer<ffi.Void> data;
  external ffi.Pointer<_GList> next;
  external ffi.Pointer<_GList> prev;
}

/// `GError`: a quark, a code and a message GLib owns until `g_error_free`.
final class _GError extends ffi.Struct {
  @ffi.Uint32()
  external int domain;
  @ffi.Int32()
  external int code;
  external ffi.Pointer<Utf8> message;
}

/// The default `GAppInfo*` for a type, or NULL. **Transfer-full**: unref it.
///
/// `must_support_uris` is false: a handler that only takes local paths is still
/// the user's choice, and GIO hands it a FUSE path for a remote file.
@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Int)>(
  symbol: 'g_app_info_get_default_for_type',
)
external ffi.Pointer<ffi.Void> _gAppInfoGetDefaultForType(
  ffi.Pointer<Utf8> contentType,
  int mustSupportUris,
);

/// Applications that declare [contentType] exactly — not through a parent type —
/// plus the user's added associations. Transfer-full on both levels.
@ffi.Native<ffi.Pointer<_GList> Function(ffi.Pointer<Utf8>)>(
  symbol: 'g_app_info_get_recommended_for_type',
)
external ffi.Pointer<_GList> _gAppInfoGetRecommendedForType(
  ffi.Pointer<Utf8> contentType,
);

/// [_gAppInfoGetRecommendedForType] plus the fallbacks GIO finds through
/// subclassing — every text editor for a Python script. Transfer-full.
@ffi.Native<ffi.Pointer<_GList> Function(ffi.Pointer<Utf8>)>(
  symbol: 'g_app_info_get_all_for_type',
)
external ffi.Pointer<_GList> _gAppInfoGetAllForType(
  ffi.Pointer<Utf8> contentType,
);

/// Every registered application, hidden ones included. Transfer-full.
@ffi.Native<ffi.Pointer<_GList> Function()>(symbol: 'g_app_info_get_all')
external ffi.Pointer<_GList> _gAppInfoGetAll();

/// The entry's `MimeType=`, NULL-terminated, owned by the appinfo.
@ffi.Native<ffi.Pointer<ffi.Pointer<Utf8>> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'g_app_info_get_supported_types',
)
external ffi.Pointer<ffi.Pointer<Utf8>> _gAppInfoGetSupportedTypes(
  ffi.Pointer<ffi.Void> appInfo,
);

/// Writes `[Default Applications]` (and an added association) into the user's
/// `mimeapps.list`, then invalidates GIO's own cache of it, so the next read in
/// this process already sees the change.
@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Pointer<_GError>>,
  )
>(symbol: 'g_app_info_set_as_default_for_type')
external int _gAppInfoSetAsDefaultForType(
  ffi.Pointer<ffi.Void> appInfo,
  ffi.Pointer<Utf8> contentType,
  ffi.Pointer<ffi.Pointer<_GError>> error,
);

/// Removes every change the user's `mimeapps.list` makes for [contentType] —
/// the default, added and removed associations — so the system's answer applies
/// again.
@ffi.Native<ffi.Void Function(ffi.Pointer<Utf8>)>(
  symbol: 'g_app_info_reset_type_associations',
)
external void _gAppInfoResetTypeAssociations(ffi.Pointer<Utf8> contentType);

/// A `GDesktopAppInfo*` by desktop-file id, or NULL. Caller owns one ref.
@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)>(
  symbol: 'g_desktop_app_info_new',
)
external ffi.Pointer<ffi.Void> _gDesktopAppInfoNew(ffi.Pointer<Utf8> desktopId);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'g_app_info_get_id',
)
external ffi.Pointer<Utf8> _gAppInfoGetId(ffi.Pointer<ffi.Void> appInfo);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'g_app_info_get_name',
)
external ffi.Pointer<Utf8> _gAppInfoGetName(ffi.Pointer<ffi.Void> appInfo);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'g_app_info_get_icon',
)
external ffi.Pointer<ffi.Void> _gAppInfoGetIcon(ffi.Pointer<ffi.Void> appInfo);

/// Newly allocated — `g_free` it.
@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'g_icon_to_string',
)
external ffi.Pointer<Utf8> _gIconToString(ffi.Pointer<ffi.Void> icon);

/// shared-mime-info's human description of a type — "PNG image". Newly
/// allocated — `g_free` it.
@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>)>(
  symbol: 'g_content_type_get_description',
)
external ffi.Pointer<Utf8> _gContentTypeGetDescription(
  ffi.Pointer<Utf8> contentType,
);

/// `$XDG_CONFIG_HOME`, as GLib resolved it — the directory GIO writes
/// `mimeapps.list` into. Owned by GLib.
@ffi.Native<ffi.Pointer<Utf8> Function()>(symbol: 'g_get_user_config_dir')
external ffi.Pointer<Utf8> _gGetUserConfigDir();

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(symbol: 'g_object_unref')
external void _gObjectUnref(ffi.Pointer<ffi.Void> object);

@ffi.Native<ffi.Void Function(ffi.Pointer<_GList>)>(symbol: 'g_list_free')
external void _gListFree(ffi.Pointer<_GList> list);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(symbol: 'g_free')
external void _gFree(ffi.Pointer<ffi.Void> value);

@ffi.Native<ffi.Void Function(ffi.Pointer<_GError>)>(symbol: 'g_error_free')
external void _gErrorFree(ffi.Pointer<_GError> error);

// ---------------------------------------------------------------------------
// The seam
// ---------------------------------------------------------------------------

/// A write GIO refused, with GLib's own words for why.
class DefaultAppException implements Exception {
  const DefaultAppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the Default Apps pane needs from the system's associations.
///
/// Every method may throw — an FFI symbol GLib does not export is an
/// `ArgumentError` at the first call — and `DefaultAppsStore` turns any throw
/// into a visible failure with a retry, never a page that silently lists
/// nothing.
abstract interface class DefaultAppAssociations {
  /// What opens [type] now, or null when nothing does.
  HandlerApp? defaultFor(String type);

  /// Applications declaring [type] itself, for a "Defaults" row.
  List<HandlerApp> recommendedFor(String type);

  /// Every application that can open [type], subclass fallbacks included, for
  /// a row of the full list.
  List<HandlerApp> allFor(String type);

  /// The types the application [appId] declares in its `MimeType=`.
  List<String> declaredTypes(String appId);

  /// Every type some installed application declares — the full list's rows.
  Set<String> handledTypes();

  /// Makes [appId] the default for [type]. Throws [DefaultAppException].
  void setDefault(String appId, String type);

  /// Drops the user's own choices for [type].
  void reset(String type);

  /// shared-mime-info's description of [type], or empty.
  String describe(String type);

  /// The types the user's own `mimeapps.list` names a default for — the rows
  /// with something to reset.
  Set<String> userDefaults();

  /// The file [setDefault] writes, for prose.
  String get userListPath;

  /// Lists that exist and outrank [userListPath] — `$desktop-mimeapps.list` in
  /// the same directory. A choice that did not take is nearly always one of
  /// these naming something else, and GIO writes only the generic file.
  List<String> overridingLists();
}

// ---------------------------------------------------------------------------
// GIO implementation
// ---------------------------------------------------------------------------

/// [DefaultAppAssociations] over the GIO already mapped into this process.
class GioDefaultAppAssociations implements DefaultAppAssociations {
  const GioDefaultAppAssociations();

  @override
  HandlerApp? defaultFor(String type) => using((arena) {
    final appInfo = _gAppInfoGetDefaultForType(
      type.toNativeUtf8(allocator: arena),
      0,
    );
    if (appInfo == ffi.nullptr) return null;
    try {
      return _handler(appInfo);
    } finally {
      _gObjectUnref(appInfo);
    }
  });

  @override
  List<HandlerApp> recommendedFor(String type) => using(
    (arena) => _drain(
      _gAppInfoGetRecommendedForType(type.toNativeUtf8(allocator: arena)),
      _handler,
    ).whereType<HandlerApp>().toList(),
  );

  @override
  List<HandlerApp> allFor(String type) => using(
    (arena) => _drain(
      _gAppInfoGetAllForType(type.toNativeUtf8(allocator: arena)),
      _handler,
    ).whereType<HandlerApp>().toList(),
  );

  @override
  List<String> declaredTypes(String appId) => using((arena) {
    final appInfo = _gDesktopAppInfoNew(appId.toNativeUtf8(allocator: arena));
    if (appInfo == ffi.nullptr) return const <String>[];
    try {
      return _supportedTypes(appInfo);
    } finally {
      _gObjectUnref(appInfo);
    }
  });

  @override
  Set<String> handledTypes() {
    final types = <String>{};
    for (final declared in _drain(_gAppInfoGetAll(), _supportedTypes)) {
      types.addAll(declared);
    }
    return types;
  }

  @override
  void setDefault(String appId, String type) => using((arena) {
    final appInfo = _gDesktopAppInfoNew(appId.toNativeUtf8(allocator: arena));
    if (appInfo == ffi.nullptr) {
      throw DefaultAppException(
        '$appId is no longer installed, so it cannot be made the default.',
      );
    }
    final error = arena<ffi.Pointer<_GError>>()..value = ffi.nullptr;
    try {
      final ok = _gAppInfoSetAsDefaultForType(
        appInfo,
        type.toNativeUtf8(allocator: arena),
        error,
      );
      if (ok != 0) return;
      final gError = error.value;
      var message = 'GIO could not save the default for $type.';
      if (gError != ffi.nullptr) {
        final text = gError.ref.message;
        if (text != ffi.nullptr) message = text.toDartString();
        _gErrorFree(gError);
      }
      throw DefaultAppException(message);
    } finally {
      _gObjectUnref(appInfo);
    }
  });

  @override
  void reset(String type) => using(
    (arena) =>
        _gAppInfoResetTypeAssociations(type.toNativeUtf8(allocator: arena)),
  );

  @override
  String describe(String type) => using((arena) {
    final description = _gContentTypeGetDescription(
      type.toNativeUtf8(allocator: arena),
    );
    if (description == ffi.nullptr) return '';
    try {
      return description.toDartString();
    } finally {
      _gFree(description.cast());
    }
  });

  @override
  Set<String> userDefaults() {
    try {
      final file = File(userListPath);
      if (!file.existsSync()) return const <String>{};
      return parseMimeAppsDefaults(file.readAsStringSync());
    } on FileSystemException {
      // Unreadable is not a failure of the pane: it costs the reset buttons,
      // and GIO, which reads the same file, will say so on a write.
      return const <String>{};
    }
  }

  String get _configDir => _gGetUserConfigDir().toDartString();

  @override
  String get userListPath => '$_configDir/mimeapps.list';

  @override
  List<String> overridingLists() {
    final desktops = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
        .split(':')
        .map((d) => d.trim().toLowerCase())
        .where((d) => d.isNotEmpty);
    return [
      for (final desktop in desktops)
        if (File('$_configDir/$desktop-mimeapps.list').existsSync())
          '$_configDir/$desktop-mimeapps.list',
    ];
  }

  // -------------------------------------------------------------------------

  /// Maps every `GAppInfo*` in a transfer-full list through [read], then frees
  /// the elements and the spine — whatever [read] throws.
  static List<T> _drain<T>(
    ffi.Pointer<_GList> head,
    T Function(ffi.Pointer<ffi.Void> appInfo) read,
  ) {
    final values = <T>[];
    Object? failure;
    StackTrace? trace;
    for (var node = head; node != ffi.nullptr; node = node.ref.next) {
      final appInfo = node.ref.data;
      if (appInfo == ffi.nullptr) continue;
      if (failure == null) {
        try {
          values.add(read(appInfo));
        } catch (error, stack) {
          failure = error;
          trace = stack;
        }
      }
      _gObjectUnref(appInfo);
    }
    if (head != ffi.nullptr) _gListFree(head);
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return values;
  }

  /// One appinfo as a [HandlerApp], or null for one GIO cannot name — an entry
  /// with no id cannot be written into `mimeapps.list`.
  static HandlerApp? _handler(ffi.Pointer<ffi.Void> appInfo) {
    final idPtr = _gAppInfoGetId(appInfo);
    if (idPtr == ffi.nullptr) return null;
    final id = idPtr.toDartString();
    final namePtr = _gAppInfoGetName(appInfo);
    final name = namePtr == ffi.nullptr ? id : namePtr.toDartString();
    var iconName = '';
    final icon = _gAppInfoGetIcon(appInfo);
    if (icon != ffi.nullptr) {
      final serialised = _gIconToString(icon);
      if (serialised != ffi.nullptr) {
        iconName = serialised.toDartString();
        _gFree(serialised.cast());
      }
    }
    return HandlerApp(id: id, name: name, iconName: iconName);
  }

  static List<String> _supportedTypes(ffi.Pointer<ffi.Void> appInfo) {
    final strv = _gAppInfoGetSupportedTypes(appInfo);
    if (strv == ffi.nullptr) return const <String>[];
    return [
      for (var i = 0; strv[i] != ffi.nullptr; i++) strv[i].toDartString(),
    ];
  }
}
