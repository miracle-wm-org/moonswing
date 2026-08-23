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
/// This is the single in-memory source of truth for the whole process: the
/// running shell watches it as a [Listenable] and rebuilds live (see
/// [appConfig]), while the settings UI mutates it. A restart is only needed for
/// changes that recreate native layer-shell windows (panel geometry, panel set,
/// background-layer presence).
class ConfigStore extends ChangeNotifier {
  ConfigStore._(this._path, this._root) {
    _startupRestartSignature = _restartSignature();
  }

  final String _path;
  final Map<String, dynamic> _root;

  /// Signature of the restart-only fields captured when the store loaded, used
  /// by [needsRestart] to decide whether the "restart to apply" banner shows.
  late final String _startupRestartSignature;

  Timer? _saveDebounce;
  bool _disposed = false;

  static const Duration _debounce = Duration(milliseconds: 400);

  /// The process-wide store shared by the running shell and the settings UI.
  /// Populated by [initShared] during startup.
  static ConfigStore? _shared;

  /// The shared singleton. Throws if used before [initShared].
  static ConfigStore get instance {
    final store = _shared;
    if (store == null) {
      throw StateError('ConfigStore.instance used before initShared()');
    }
    return store;
  }

  /// Loads the shared singleton from the real config path. Idempotent — a
  /// second call returns the already-loaded store. Call once from `main()`.
  static Future<ConfigStore> initShared() async =>
      _shared ??= await loadFrom(AppConfig.resolveConfigPath());

  /// A freshly-derived typed [AppConfig] built from the current in-memory map.
  /// Also re-applies per-module options via [Module.loadAll] as a side effect
  /// (see [AppConfig.fromMap]), so this must be read outside of `build` — from
  /// a listener callback that then triggers a rebuild.
  AppConfig get appConfig => AppConfig.fromMap(_root);

  /// Loads and parses the config file into a mutable map. Falls back to an
  /// empty document if the file is missing or unparseable.
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

  /// True when a restart-only field has changed since the store loaded. These
  /// are values that parametrize native layer-shell windows and cannot apply
  /// live: panel `anchor`/`height`/`layer`, the set of panels, and whether the
  /// background surface exists at all (a wallpaper entry, or the desktop grid
  /// being enabled). Everything else updates live.
  bool get needsRestart => _restartSignature() != _startupRestartSignature;

  String _restartSignature() {
    final parts = <String>[];
    final panels = _root['panels'];
    if (panels is Map) {
      final keys = panels.keys.map((k) => '$k').toList()..sort();
      for (final key in keys) {
        final panel = panels[key];
        if (panel is Map) {
          parts.add('$key:${panel['anchor']}:${panel['height']}:'
              '${panel['layer']}');
        } else {
          parts.add('$key:');
        }
      }
    }
    // What is restart-only is whether the background *surface* exists, not what
    // fed that decision. Signing the decision rather than its two inputs means
    // enabling the desktop grid on a config that already has a wallpaper does
    // not demand a restart — the surface is already there. Grid geometry and
    // the item list are live and deliberately absent from the signature.
    final background = _root['background'];
    final entries = background is Map ? background['entries'] : null;
    final hasWallpaper = entries is List && entries.isNotEmpty;
    // The grid is on by default, so an absent `[desktop]` section — or a
    // wrongly-typed `enabled`, which `boolOr` also answers with the default —
    // is an *enabled* grid. Mirroring `DesktopConfig.fromMap` here is what
    // keeps this signature agreeing with the surface `main()` actually built
    // from the typed config; reading `== true` off the raw map would sign a
    // fresh config as surface-less and raise the banner on the next edit.
    final desktop = _root['desktop'];
    final rawDesktopEnabled = desktop is Map ? desktop['enabled'] : null;
    final desktopEnabled =
        rawDesktopEnabled is bool ? rawDesktopEnabled : true;
    parts.add('bg:${hasWallpaper || desktopEnabled}');
    return parts.join('|');
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

  /// The current document as TOML, or null when it holds a value TOML cannot
  /// encode — in which case the write is skipped rather than allowed to
  /// corrupt the file.
  String? _encode() {
    try {
      return TomlDocument.fromMap(_root).toString();
    } catch (_) {
      return null;
    }
  }

  /// Serializes the current document to TOML and writes it atomically.
  Future<void> save() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final toml = _encode();
    if (toml == null) return;
    try {
      final tmp = File('$_path.tmp');
      await tmp.parent.create(recursive: true);
      await tmp.writeAsString(toml, flush: true);
      await tmp.rename(_path);
    } catch (_) {
      // Disk error — leave the existing config untouched.
    }
  }

  /// The same atomic write, done synchronously — the shape `ThemeStore._write`
  /// already uses, and the only shape [dispose] can use.
  ///
  /// `dispose` cannot await, so calling `save()` there left a write in flight
  /// *after* the store was gone: in the shell that is a write racing process
  /// exit, and in a test it is a `.tmp` file landing in a temp directory the
  /// harness has already started deleting, which surfaces as an unrelated
  /// `Directory not empty` failure in whichever test happens to lose the race.
  void _saveSync() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final toml = _encode();
    if (toml == null) return;
    try {
      final tmp = File('$_path.tmp');
      tmp.parent.createSync(recursive: true);
      tmp.writeAsStringSync(toml, flush: true);
      tmp.renameSync(_path);
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
    // Best-effort flush of any queued change before tearing down, synchronously
    // so that nothing outlives the store — see [_saveSync].
    if (_saveDebounce?.isActive ?? false) {
      _saveSync();
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
