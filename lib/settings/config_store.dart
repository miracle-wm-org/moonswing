import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config.dart';

/// Read/mutate/write layer for graceful-shell's own `config.toml`.
///
/// [config.toml] is the single source of truth. This store loads a mutable
/// deep copy of the parsed document, exposes nested key-path access, and writes
/// changes back atomically (temp file + rename) with a short debounce so that
/// dragging a slider or typing in a field does not thrash the disk.
///
/// Changes are consumed by [AppConfig.load] on the next launch — the running
/// app is not live-reloaded (see the settings "restart to apply" banner).
class ConfigStore extends ChangeNotifier {
  ConfigStore._(this._path, this._root);

  final String _path;
  final Map<String, dynamic> _root;

  Timer? _saveDebounce;
  bool _disposed = false;

  static const Duration _debounce = Duration(milliseconds: 400);

  /// Loads and parses the config file into a mutable map. Falls back to an
  /// empty document if the file is missing or unparseable.
  static Future<ConfigStore> load() => loadFrom(AppConfig.resolveConfigPath());

  /// Loads a store from an explicit [path]. Exposed for tests so they never
  /// touch the user's real `config.toml`.
  @visibleForTesting
  static Future<ConfigStore> loadFrom(String path) async {
    Map<String, dynamic> root;
    try {
      final doc = await TomlDocument.load(path);
      root = _deepCopyMap(doc.toMap());
    } catch (_) {
      root = <String, dynamic>{};
    }
    return ConfigStore._(path, root);
  }

  /// Reads the value at [path] (e.g. `['theme', 'accent']`), or null if any
  /// segment is missing or the leaf is not a [T].
  T? get<T>(List<String> path) {
    dynamic node = _root;
    for (final key in path) {
      if (node is Map && node.containsKey(key)) {
        node = node[key];
      } else {
        return null;
      }
    }
    return node is T ? node : null;
  }

  /// Reads the list at [path] as a `List<T>` (empty if absent/wrong type).
  List<T> getList<T>(List<String> path) {
    final value = get<List>(path);
    if (value == null) return <T>[];
    return value.whereType<T>().toList();
  }

  /// Sets [value] at [path], creating intermediate maps as needed, then
  /// schedules a debounced save. Passing a null [value] removes the key.
  void set(List<String> path, Object? value) {
    if (value == null) {
      remove(path);
      return;
    }
    if (path.isEmpty) return;
    Map<String, dynamic> node = _root;
    for (var i = 0; i < path.length - 1; i++) {
      final key = path[i];
      final child = node[key];
      if (child is Map<String, dynamic>) {
        node = child;
      } else {
        final created = <String, dynamic>{};
        node[key] = created;
        node = created;
      }
    }
    node[path.last] = value;
    _onChanged();
  }

  /// Removes the key at [path] (no-op if absent), then schedules a save.
  void remove(List<String> path) {
    if (path.isEmpty) return;
    dynamic node = _root;
    for (var i = 0; i < path.length - 1; i++) {
      final key = path[i];
      if (node is Map && node[key] is Map) {
        node = node[key];
      } else {
        return; // nothing to remove
      }
    }
    if (node is Map && node.containsKey(path.last)) {
      node.remove(path.last);
      _onChanged();
    }
  }

  /// The top-level table names under `[panels]`, in document order.
  List<String> get panelNames {
    final panels = _root['panels'];
    if (panels is Map) return panels.keys.whereType<String>().toList();
    return const [];
  }

  void _onChanged() {
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_debounce, () {
      // Fire-and-forget; errors are swallowed so a transient write failure
      // never crashes the settings UI.
      save();
    });
  }

  /// Serializes the current document to TOML and writes it atomically.
  Future<void> save() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final String toml;
    try {
      toml = TomlDocument.fromMap(_root).toString();
    } catch (_) {
      return; // un-encodable value; skip this write rather than corrupt.
    }
    try {
      final tmp = File('$_path.tmp');
      await tmp.parent.create(recursive: true);
      await tmp.writeAsString(toml, flush: true);
      await tmp.rename(_path);
    } catch (_) {
      // Disk error — leave the existing config untouched.
    }
  }

  /// Flushes any pending debounced write immediately.
  Future<void> flush() async {
    if (_saveDebounce?.isActive ?? false) {
      await save();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Best-effort flush of any queued change before tearing down.
    if (_saveDebounce?.isActive ?? false) {
      save();
    }
    _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Deep copy — TomlDocument.toMap() returns unmodifiable maps/lists.
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _deepCopyMap(Map<dynamic, dynamic> src) {
    final out = <String, dynamic>{};
    for (final entry in src.entries) {
      out['${entry.key}'] = _deepCopyValue(entry.value);
    }
    return out;
  }

  static dynamic _deepCopyValue(dynamic value) {
    if (value is Map) return _deepCopyMap(value);
    if (value is List) return value.map(_deepCopyValue).toList();
    return value;
  }
}
