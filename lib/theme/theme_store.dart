import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/theme/builtin_themes.dart';

/// One theme file, as the picker sees it.
@immutable
class ThemeSummary {
  const ThemeSummary({
    required this.slug,
    required this.displayName,
    required this.builtIn,
    required this.config,
  });

  /// The file's basename without `.toml` — what `config.toml` names.
  final String slug;

  /// The `name` key, or a title-cased [slug] when the file omits it.
  final String displayName;

  /// Whether this theme ships with the shell and is therefore read-only.
  final bool builtIn;

  final ThemeConfig config;
}

/// The live palette, and the catalogue of palettes to choose from.
///
/// Same singleton-[ChangeNotifier] shape as `OsdStore`/`AppIndex`: one
/// instance for the process, a `@visibleForTesting` factory that takes its own
/// directory, and an idempotent [start] called from `main()`.
///
/// Two rules hold this together:
///
/// * **`config.toml` names the theme; this store owns its contents.** The
///   store listens to [ConfigStore] for the `theme` key alone and never reads
///   `ConfigStore.appConfig`, whose getter re-runs `Module.loadAll` as a side
///   effect — that would fire on every keystroke anywhere in the settings UI.
/// * **Shipped themes are read-only.** [edit] silently forks a built-in into a
///   user copy before applying the change, so `themes/dracula.toml` stays
///   byte-identical to what the shell seeded and can be re-seeded safely.
class ThemeStore extends ChangeNotifier {
  ThemeStore._(this._directory);

  /// The process-wide store, watched by every `ThemeProvider`.
  static final ThemeStore instance = ThemeStore._(resolveThemesDir());

  /// A store rooted at [directory]. Tests always pass a temp dir — never the
  /// user's real `~/.config/graceful-shell/themes`.
  @visibleForTesting
  factory ThemeStore.forTesting({required String directory}) =>
      ThemeStore._(directory);

  /// Mirrors [AppConfig.resolveConfigPath] so the two never drift.
  static String resolveThemesDir() {
    final homeDir = Platform.environment['HOME'] ?? '';
    final configHome =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$homeDir/.config';
    return '$configHome/graceful-shell/themes';
  }

  static const Duration _debounce = Duration(milliseconds: 400);

  final String _directory;

  /// slug -> summary, in display order (built-ins first).
  final Map<String, ThemeSummary> _themes = {};

  /// slug -> the file's parsed key/value map, kept so that a `name` key and
  /// any keys this version does not understand survive a round-trip.
  final Map<String, Map<String, dynamic>> _raw = {};

  String _activeName = kDefaultThemeName;
  ThemeConfig _theme = const ThemeConfig();

  ConfigStore? _config;
  Timer? _saveDebounce;
  final Set<String> _pendingWrites = {};
  bool _started = false;
  bool _disposed = false;

  /// The resolved active palette. Never null: an unknown name, an unreadable
  /// file or unparseable TOML all land on the built-in default.
  ThemeConfig get theme => _theme;

  /// The slug of the active theme.
  String get activeName => _activeName;

  /// Whether the active theme ships with the shell, and so cannot be edited
  /// in place.
  bool get activeIsBuiltIn => kBuiltInThemes.containsKey(_activeName);

  /// Every theme on disk, built-ins first then user themes alphabetically.
  List<ThemeSummary> get themes => List.unmodifiable(_themes.values);

  /// The directory theme files live in. Exposed for the settings UI's hint.
  String get directory => _directory;

  /// Seeds any missing built-in, indexes the directory, and binds to
  /// [config] so that a change to its `theme` key restyles the shell.
  ///
  /// Safe to call more than once.
  void start({ConfigStore? config}) {
    if (!_started) {
      _started = true;
      _seedBuiltIns();
      _reindex();
    }
    if (config != null && _config == null) {
      _config = config;
      config.addListener(_onConfigChanged);
    }
    // Resolve unconditionally rather than leaning on _onConfigChanged's
    // early-return: at this point _theme is still the field initialiser, which
    // only *happens* to match the default theme's file.
    _resolveActive(_selectedName());
    notifyListeners();
  }

  /// Re-reads the themes directory. The settings UI is the only writer today,
  /// so nothing calls this automatically — it is the seam for a file watcher.
  void refresh() {
    _reindex();
    _resolveActive(_activeName);
    notifyListeners();
  }

  /// Makes [slug] the active theme.
  ///
  /// Routed through [ConfigStore] when one is bound so there is a single path
  /// in: the store's own listener is what actually swaps the palette.
  void select(String slug) {
    if (!_themes.containsKey(slug)) return;
    final config = _config;
    if (config != null) {
      config.set(['theme'], slug);
    } else {
      _resolveActive(slug);
      notifyListeners();
    }
  }

  /// Creates a theme named [displayName], copying [from] (the active theme by
  /// default), and selects it. Returns the new slug, or null if the name
  /// slugifies to nothing.
  String? create(String displayName, {String? from}) {
    final trimmed = displayName.trim();
    final base = _slugify(trimmed);
    if (base.isEmpty) return null;
    final source = _raw[from ?? _activeName] ?? _theme.toMap();
    final slug = _uniqueSlug(base);
    final map = <String, dynamic>{
      ...source,
      'name': trimmed,
    };
    _raw[slug] = map;
    _write(slug, map);
    _reindex();
    select(slug);
    notifyListeners();
    return slug;
  }

  /// Duplicates the active theme under an auto-generated name and selects the
  /// copy. This is what an edit to a built-in triggers.
  String? duplicateActive() {
    final current = _themes[_activeName];
    final name = current == null ? 'Custom' : '${current.displayName} (custom)';
    return create(name);
  }

  /// Sets a single key on the active theme, forking it first if it is a
  /// built-in. [key] is a TOML key — a colour name, `font`, or `blur`.
  void edit(String key, Object value) {
    if (activeIsBuiltIn && duplicateActive() == null) return;
    final map = _raw[_activeName];
    if (map == null) return;
    map[key] = value;
    _resolveActive(_activeName);
    _reindexOne(_activeName);
    _scheduleWrite(_activeName);
    notifyListeners();
  }

  /// Renames the active theme's display name (not its filename).
  void rename(String displayName) {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;
    edit('name', trimmed);
  }

  /// Deletes a user theme. Built-ins refuse — they would only be re-seeded on
  /// the next start anyway. Returns whether anything was deleted.
  bool delete(String slug) {
    if (kBuiltInThemes.containsKey(slug)) return false;
    if (!_themes.containsKey(slug)) return false;
    _pendingWrites.remove(slug);
    try {
      final file = File('$_directory/$slug.toml');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Read-only directory; the entry is gone from the index either way and
      // the next reindex will bring it back. Nothing else to do.
    }
    _themes.remove(slug);
    _raw.remove(slug);
    if (_activeName == slug) {
      select(kDefaultThemeName);
    }
    _reindex();
    notifyListeners();
    return true;
  }

  /// Forces any debounced write to disk. Called before shutdown and by tests.
  Future<void> flush() async => _flushSync();

  void _flushSync() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (_pendingWrites.isEmpty) return;
    final pending = _pendingWrites.toList();
    _pendingWrites.clear();
    for (final slug in pending) {
      final map = _raw[slug];
      if (map != null) _write(slug, map);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _config?.removeListener(_onConfigChanged);
    _saveDebounce?.cancel();
    _saveDebounce = null;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // -- internals ------------------------------------------------------------

  /// The theme `config.toml` names, falling back to the default.
  ///
  /// Deliberately not `ConfigStore.appConfig`: that getter rebuilds the whole
  /// typed config and re-applies every module's options as a side effect,
  /// which would fire on every keystroke anywhere in the settings UI.
  String _selectedName() {
    final name = _config?.get<String>(['theme'])?.trim();
    return (name == null || name.isEmpty) ? kDefaultThemeName : name;
  }

  void _onConfigChanged() {
    final next = _selectedName();
    if (next == _activeName) return;
    _resolveActive(next);
    notifyListeners();
  }

  /// Writes any built-in whose file is missing *or out of date*.
  ///
  /// The shell owns these files; [edit] forks rather than touching them, so
  /// there is nothing of the user's to lose. Leaving a stale copy in place
  /// instead would mean a palette fix never reaches anyone who has already run
  /// the shell once — which is exactly what happened when the panel gained its
  /// own colour: the shipped `glassy.toml` on disk kept the old keys and the
  /// bar stayed opaque. Someone who wants their own version duplicates it.
  void _seedBuiltIns() {
    try {
      final dir = Directory(_directory);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      for (final entry in kBuiltInThemes.entries) {
        final file = File('$_directory/${entry.key}.toml');
        if (file.existsSync() && file.readAsStringSync() == entry.value) {
          continue;
        }
        file.writeAsStringSync(entry.value);
      }
    } catch (_) {
      // No themes directory (read-only home, sandbox). The built-ins are still
      // reachable in memory via _reindex's fallback, so the shell is styled.
    }
  }

  void _reindex() {
    // Re-reading the directory replaces every in-memory map, so any edit still
    // sitting in the debounce has to reach disk first or it is lost.
    _flushSync();
    _themes.clear();
    final found = <String, Map<String, dynamic>>{};

    // Parse every *.toml in the directory.
    try {
      final dir = Directory(_directory);
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is! File || !entity.path.endsWith('.toml')) continue;
          final slug = entity.uri.pathSegments.last
              .substring(0, entity.uri.pathSegments.last.length - 5);
          final map = _parse(() => entity.readAsStringSync());
          if (map != null) found[slug] = map;
        }
      }
    } catch (_) {
      // Unreadable directory; fall through to the embedded built-ins.
    }

    // A built-in that could not be read from disk still has to be selectable,
    // or a sandboxed shell would have an empty picker.
    for (final entry in kBuiltInThemes.entries) {
      found.putIfAbsent(entry.key, () {
        final map = _parse(() => entry.value);
        return map ?? <String, dynamic>{};
      });
    }

    _raw
      ..clear()
      ..addAll(found);

    final slugs = found.keys.toList()
      ..sort((a, b) {
        final aBuiltIn = kBuiltInThemes.containsKey(a);
        final bBuiltIn = kBuiltInThemes.containsKey(b);
        if (aBuiltIn != bBuiltIn) return aBuiltIn ? -1 : 1;
        return a.compareTo(b);
      });
    for (final slug in slugs) {
      _themes[slug] = _summaryFor(slug, found[slug]!);
    }
  }

  void _reindexOne(String slug) {
    final map = _raw[slug];
    if (map == null) return;
    _themes[slug] = _summaryFor(slug, map);
  }

  ThemeSummary _summaryFor(String slug, Map<String, dynamic> map) {
    final rawName = map['name'];
    return ThemeSummary(
      slug: slug,
      displayName: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : _titleCase(slug),
      builtIn: kBuiltInThemes.containsKey(slug),
      config: ThemeConfig.fromMap(map),
    );
  }

  ThemeConfig _resolve(String slug) {
    final map = _raw[slug] ?? _raw[kDefaultThemeName];
    return ThemeConfig.fromMap(map);
  }

  void _resolveActive(String slug) {
    _activeName = slug;
    _theme = _resolve(slug);
  }

  Map<String, dynamic>? _parse(String Function() read) {
    try {
      return _deepCopy(TomlDocument.parse(read()).toMap());
    } catch (_) {
      // Missing file or malformed TOML — the caller falls back.
      return null;
    }
  }

  void _scheduleWrite(String slug) {
    _pendingWrites.add(slug);
    _saveDebounce?.cancel();
    // The colour picker emits on every drag frame, so writing eagerly would
    // thrash the disk. Same 400ms debounce ConfigStore uses.
    _saveDebounce = Timer(_debounce, _flushSync);
  }

  /// Serializes [map] and replaces `$slug.toml` atomically — temp file then
  /// rename, the same shape as `ConfigStore.save()`.
  void _write(String slug, Map<String, dynamic> map) {
    final String toml;
    try {
      toml = TomlDocument.fromMap(map).toString();
    } catch (_) {
      return; // un-encodable value; skip rather than corrupt the file.
    }
    try {
      final path = '$_directory/$slug.toml';
      final tmp = File('$path.tmp');
      tmp.parent.createSync(recursive: true);
      tmp.writeAsStringSync(toml, flush: true);
      tmp.renameSync(path);
    } catch (_) {
      // Disk error — leave the existing file untouched.
    }
  }

  String _uniqueSlug(String base) {
    if (!_themes.containsKey(base) && !_raw.containsKey(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base-$i';
      if (!_themes.containsKey(candidate) && !_raw.containsKey(candidate)) {
        return candidate;
      }
    }
  }

  static String _slugify(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static String _titleCase(String slug) => slug
      .split(RegExp(r'[-_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// `TomlDocument.toMap()` hands back unmodifiable maps; [edit] needs to
  /// mutate one in place.
  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) => {
        for (final e in source.entries)
          e.key: e.value is Map<String, dynamic>
              ? _deepCopy(e.value as Map<String, dynamic>)
              : e.value is List
                  ? List<dynamic>.from(e.value as List)
                  : e.value,
      };
}

/// Seeds the shipped themes and resolves the active one. Called from `main()`
/// beside the other `start*Service` functions, after [ConfigStore.initShared].
void startThemeService(ConfigStore config) =>
    ThemeStore.instance.start(config: config);
