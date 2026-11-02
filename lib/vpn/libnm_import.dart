// Importing a VPN file through the plugin that understands it, over libnm.
//
// A `.ovpn`, a PPTP or vpnc `.pcf`, an OpenConnect profile: each format is
// parsed by its own NetworkManager plugin, in the libnm half of it
// (`libnm-vpn-plugin-openvpn.so` …) that `nmcli connection import` and every
// desktop's connection editor load. NetworkManager offers no D-Bus call for it
// and there is no Dart package, so this is that same path over `dart:ffi`:
//
//   nm_vpn_plugin_info_new_from_file(".name")   the plugin's registration
//   nm_vpn_plugin_info_load_editor_plugin()     its libnm half, dlopened
//   nm_vpn_editor_plugin_import(path)           → NMConnection
//   nm_connection_to_dbus()                     → the a{sa{sv}} GVariant
//
// and the GVariant is walked into `package:dbus` values, which is what
// `AddConnection` is then sent. The plugin does the format's hard parts —
// OpenVPN's inline `<ca>` blocks are written out to files under `~/.cert/`,
// as `nmcli` would — so a profile imported here is the one any other tool
// would have made.
//
// libnm is `dlopen`ed, like libpam: the shell builds and runs without it, and
// only Import says so.
library;

import 'dart:ffi' as ffi;

import 'package:dbus/dbus.dart';
import 'package:ffi/ffi.dart';

import 'package:moonswing/native/ffi_util.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';

/// Why a file could not be imported, worded for the user.
class VpnImportException implements Exception {
  const VpnImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Hands a file to the installed plugins. Behind an interface so the store's
/// tests never load a native library.
abstract interface class VpnPluginImporter {
  /// The settings the first of [plugins] able to read [path] made of it.
  /// Throws a [VpnImportException] when none could.
  NmSettings importFile(String path, List<VpnPluginInfo> plugins);
}

final class _GError extends ffi.Struct {
  @ffi.Uint32()
  external int domain;
  @ffi.Int32()
  external int code;
  external ffi.Pointer<Utf8> message;
}

typedef _Ptr = ffi.Pointer<ffi.Void>;

/// An opaque GLib pointer — a `GVariant *` where [GVariantReader] takes one.
typedef GPointer = ffi.Pointer<ffi.Void>;
typedef _ErrOut = ffi.Pointer<ffi.Pointer<_GError>>;

/// `NM_VPN_EDITOR_PLUGIN_CAPABILITY_IMPORT`.
const int _capabilityImport = 0x1;

/// `NM_CONNECTION_SERIALIZE_ALL`: settings and secrets — a `.ovpn`'s inline
/// key password, a `.pcf`'s group secret, are part of what was imported.
const int _serializeAll = 0;

/// The libnm entry points, resolved once. Everything GLib is looked up through
/// libnm's own handle, whose dependency tree has it — a `flutter_tester` run
/// has no GLib in the process to find it by.
class _Libnm {
  _Libnm(ffi.DynamicLibrary lib)
    : pluginInfoNewFromFile = lib
          .lookupFunction<
            _Ptr Function(ffi.Pointer<Utf8>, _ErrOut),
            _Ptr Function(ffi.Pointer<Utf8>, _ErrOut)
          >('nm_vpn_plugin_info_new_from_file'),
      loadEditorPlugin = lib
          .lookupFunction<
            _Ptr Function(_Ptr, _ErrOut),
            _Ptr Function(_Ptr, _ErrOut)
          >('nm_vpn_plugin_info_load_editor_plugin'),
      capabilities = lib
          .lookupFunction<ffi.Uint32 Function(_Ptr), int Function(_Ptr)>(
            'nm_vpn_editor_plugin_get_capabilities',
          ),
      import = lib
          .lookupFunction<
            _Ptr Function(_Ptr, ffi.Pointer<Utf8>, _ErrOut),
            _Ptr Function(_Ptr, ffi.Pointer<Utf8>, _ErrOut)
          >('nm_vpn_editor_plugin_import'),
      toDbus = lib
          .lookupFunction<
            _Ptr Function(_Ptr, ffi.Uint32),
            _Ptr Function(_Ptr, int)
          >('nm_connection_to_dbus'),
      objectUnref = lib
          .lookupFunction<ffi.Void Function(_Ptr), void Function(_Ptr)>(
            'g_object_unref',
          ),
      errorFree = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<_GError>),
            void Function(ffi.Pointer<_GError>)
          >('g_error_free'),
      variant = GVariantReader(lib);

  final _Ptr Function(ffi.Pointer<Utf8>, _ErrOut) pluginInfoNewFromFile;
  final _Ptr Function(_Ptr, _ErrOut) loadEditorPlugin;
  final int Function(_Ptr) capabilities;
  final _Ptr Function(_Ptr, ffi.Pointer<Utf8>, _ErrOut) import;
  final _Ptr Function(_Ptr, int) toDbus;
  final void Function(_Ptr) objectUnref;
  final void Function(ffi.Pointer<_GError>) errorFree;
  final GVariantReader variant;

  /// The message of a set error, freeing it; null for none.
  String? takeError(_ErrOut out) {
    final error = out.value;
    if (error == ffi.nullptr) return null;
    final message = error.ref.message == ffi.nullptr
        ? 'unknown error'
        : error.ref.message.toDartString();
    errorFree(error);
    out.value = ffi.nullptr;
    return message;
  }
}

/// The importer over the machine's libnm.
class LibnmImporter implements VpnPluginImporter {
  LibnmImporter({List<String> sonames = const ['libnm.so.0', 'libnm.so']})
    : _sonames = sonames;

  final List<String> _sonames;
  _Libnm? _lib;
  bool _missing = false;

  _Libnm _open() {
    final open = _lib;
    if (open != null) return open;
    if (!_missing) {
      final lib = openFirstLibrary(_sonames);
      if (lib != null) {
        try {
          return _lib = _Libnm(lib);
        } on ArgumentError {
          // A libnm older than 1.4 lacks the plugin-info calls.
        }
      }
      _missing = true;
    }
    throw const VpnImportException(
      'Importing needs NetworkManager\'s client library, libnm (1.4 or newer), '
      'which is not installed.',
    );
  }

  @override
  NmSettings importFile(String path, List<VpnPluginInfo> plugins) {
    final candidates = [
      for (final p in plugins)
        if (p.libnmPlugin.isNotEmpty) p,
    ];
    if (candidates.isEmpty) {
      throw const VpnImportException(
        'No NetworkManager VPN plugin that imports files is installed — '
        'NetworkManager-openvpn reads .ovpn files.',
      );
    }
    final nm = _open();
    final failures = <String>[];
    return using((arena) {
      final err = arena<ffi.Pointer<_GError>>()..value = ffi.nullptr;
      final cPath = path.toNativeUtf8(allocator: arena);
      for (final plugin in candidates) {
        final info = nm.pluginInfoNewFromFile(
          plugin.file.toNativeUtf8(allocator: arena),
          err,
        );
        final infoError = nm.takeError(err);
        if (info == ffi.nullptr) {
          failures.add('${plugin.name}: ${infoError ?? 'not loadable'}');
          continue;
        }
        try {
          // Transfer none: the editor plugin is the info's, and dies with it.
          final editor = nm.loadEditorPlugin(info, err);
          final editorError = nm.takeError(err);
          if (editor == ffi.nullptr) {
            failures.add('${plugin.name}: ${editorError ?? 'not loadable'}');
            continue;
          }
          if (nm.capabilities(editor) & _capabilityImport == 0) continue;
          final connection = nm.import(editor, cPath, err);
          final importError = nm.takeError(err);
          if (connection == ffi.nullptr) {
            // The expected answer from every plugin but the file's own.
            if (importError != null) failures.add(importError);
            continue;
          }
          try {
            final variant = nm.toDbus(connection, _serializeAll);
            if (variant == ffi.nullptr) {
              throw VpnImportException(
                'The ${plugin.name} plugin read the file but produced no '
                'settings.',
              );
            }
            final value = nm.variant.readOwned(variant);
            final settings = nmSettingsFromValue(value);
            if (settings.isEmpty) {
              throw VpnImportException(
                'The ${plugin.name} plugin read the file but produced no '
                'settings.',
              );
            }
            return settings;
          } finally {
            nm.objectUnref(connection);
          }
        } finally {
          nm.objectUnref(info);
        }
      }
      throw VpnImportException(
        failures.isEmpty
            ? 'None of the installed VPN plugins recognised this file.'
            : 'None of the installed VPN plugins could read this file '
                  '(${failures.first}).',
      );
    });
  }
}

/// Reads a GVariant into the `package:dbus` value of the same type.
///
/// Every type a connection's settings use is a D-Bus type, so the walk is
/// total over them; a GVariant-only type (maybe, handle) is refused rather
/// than guessed at.
class GVariantReader {
  GVariantReader(ffi.DynamicLibrary lib)
    : _typeString = lib
          .lookupFunction<
            ffi.Pointer<Utf8> Function(_Ptr),
            ffi.Pointer<Utf8> Function(_Ptr)
          >('g_variant_get_type_string'),
      _nChildren = lib
          .lookupFunction<ffi.Size Function(_Ptr), int Function(_Ptr)>(
            'g_variant_n_children',
          ),
      _child = lib
          .lookupFunction<
            _Ptr Function(_Ptr, ffi.Size),
            _Ptr Function(_Ptr, int)
          >('g_variant_get_child_value'),
      _variant = lib.lookupFunction<_Ptr Function(_Ptr), _Ptr Function(_Ptr)>(
        'g_variant_get_variant',
      ),
      _refSink = lib.lookupFunction<_Ptr Function(_Ptr), _Ptr Function(_Ptr)>(
        'g_variant_ref_sink',
      ),
      _unref = lib.lookupFunction<ffi.Void Function(_Ptr), void Function(_Ptr)>(
        'g_variant_unref',
      ),
      _boolean = lib
          .lookupFunction<ffi.Int32 Function(_Ptr), int Function(_Ptr)>(
            'g_variant_get_boolean',
          ),
      _byte = lib.lookupFunction<ffi.Uint8 Function(_Ptr), int Function(_Ptr)>(
        'g_variant_get_byte',
      ),
      _int16 = lib.lookupFunction<ffi.Int16 Function(_Ptr), int Function(_Ptr)>(
        'g_variant_get_int16',
      ),
      _uint16 = lib
          .lookupFunction<ffi.Uint16 Function(_Ptr), int Function(_Ptr)>(
            'g_variant_get_uint16',
          ),
      _int32 = lib.lookupFunction<ffi.Int32 Function(_Ptr), int Function(_Ptr)>(
        'g_variant_get_int32',
      ),
      _uint32 = lib
          .lookupFunction<ffi.Uint32 Function(_Ptr), int Function(_Ptr)>(
            'g_variant_get_uint32',
          ),
      _int64 = lib.lookupFunction<ffi.Int64 Function(_Ptr), int Function(_Ptr)>(
        'g_variant_get_int64',
      ),
      _uint64 = lib
          .lookupFunction<ffi.Uint64 Function(_Ptr), int Function(_Ptr)>(
            'g_variant_get_uint64',
          ),
      _double = lib
          .lookupFunction<ffi.Double Function(_Ptr), double Function(_Ptr)>(
            'g_variant_get_double',
          ),
      _string = lib
          .lookupFunction<
            ffi.Pointer<Utf8> Function(_Ptr, ffi.Pointer<ffi.Size>),
            ffi.Pointer<Utf8> Function(_Ptr, ffi.Pointer<ffi.Size>)
          >('g_variant_get_string'),
      _fixedArray = lib
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(
              _Ptr,
              ffi.Pointer<ffi.Size>,
              ffi.Size,
            ),
            ffi.Pointer<ffi.Uint8> Function(_Ptr, ffi.Pointer<ffi.Size>, int)
          >('g_variant_get_fixed_array');

  final ffi.Pointer<Utf8> Function(_Ptr) _typeString;
  final int Function(_Ptr) _nChildren;
  final _Ptr Function(_Ptr, int) _child;
  final _Ptr Function(_Ptr) _variant;
  final _Ptr Function(_Ptr) _refSink;
  final void Function(_Ptr) _unref;
  final int Function(_Ptr) _boolean;
  final int Function(_Ptr) _byte;
  final int Function(_Ptr) _int16;
  final int Function(_Ptr) _uint16;
  final int Function(_Ptr) _int32;
  final int Function(_Ptr) _uint32;
  final int Function(_Ptr) _int64;
  final int Function(_Ptr) _uint64;
  final double Function(_Ptr) _double;
  final ffi.Pointer<Utf8> Function(_Ptr, ffi.Pointer<ffi.Size>) _string;
  final ffi.Pointer<ffi.Uint8> Function(_Ptr, ffi.Pointer<ffi.Size>, int)
  _fixedArray;

  /// Reads a variant this call takes ownership of — floating, as
  /// `nm_connection_to_dbus` returns one, or a full reference — and drops it.
  DBusValue readOwned(GPointer variant) {
    _refSink(variant);
    try {
      return read(variant);
    } finally {
      _unref(variant);
    }
  }

  /// Reads a variant the caller keeps.
  DBusValue read(GPointer v) {
    final type = _typeString(v).toDartString();
    switch (type[0]) {
      case 'b':
        return DBusBoolean(_boolean(v) != 0);
      case 'y':
        return DBusByte(_byte(v));
      case 'n':
        return DBusInt16(_int16(v));
      case 'q':
        return DBusUint16(_uint16(v));
      case 'i':
        return DBusInt32(_int32(v));
      case 'u':
        return DBusUint32(_uint32(v));
      case 'x':
        return DBusInt64(_int64(v));
      case 't':
        return DBusUint64(_uint64(v));
      case 'd':
        return DBusDouble(_double(v));
      case 's':
        return DBusString(_string(v, ffi.nullptr).toDartString());
      case 'o':
        return DBusObjectPath(_string(v, ffi.nullptr).toDartString());
      case 'g':
        return DBusSignature(_string(v, ffi.nullptr).toDartString());
      case 'v':
        final inner = _variant(v);
        try {
          return DBusVariant(read(inner));
        } finally {
          _unref(inner);
        }
      case 'a':
        if (type == 'ay') return _bytes(v);
        if (type[1] == '{') {
          final keyType = DBusSignature(type[2]);
          final valueType = DBusSignature(type.substring(3, type.length - 1));
          final map = <DBusValue, DBusValue>{};
          _eachChild(v, (entry) {
            final key = _child(entry, 0);
            final value = _child(entry, 1);
            try {
              map[read(key)] = read(value);
            } finally {
              _unref(key);
              _unref(value);
            }
          });
          return DBusDict(keyType, valueType, map);
        }
        final children = <DBusValue>[];
        _eachChild(v, (child) => children.add(read(child)));
        return DBusArray(DBusSignature(type.substring(1)), children);
      case '(':
        final children = <DBusValue>[];
        _eachChild(v, (child) => children.add(read(child)));
        return DBusStruct(children);
      default:
        throw VpnImportException(
          'The plugin produced a value of type "$type", which D-Bus cannot '
          'carry.',
        );
    }
  }

  void _eachChild(_Ptr v, void Function(_Ptr child) visit) {
    final n = _nChildren(v);
    for (var i = 0; i < n; i++) {
      final child = _child(v, i);
      try {
        visit(child);
      } finally {
        _unref(child);
      }
    }
  }

  DBusArray _bytes(_Ptr v) => using((arena) {
    final count = arena<ffi.Size>();
    final data = _fixedArray(v, count, 1);
    final n = count.value;
    if (n == 0 || data == ffi.nullptr) return DBusArray.byte(const []);
    return DBusArray.byte(List<int>.of(data.asTypedList(n)));
  });
}
