// The keyboard layout for the whole shell.
//
// `BatteryStore`'s singleton-with-leases shape, `WeatherStore.error`'s failure
// shape, and `ThemeStore`'s "reads `ConfigStore` for its own subtree alone"
// rule. There is one locale1 subscription for the machine however many bars,
// monitors and settings panes are looking at it.
//
// The load-bearing rule in here is that [activeIndex] is *derived* from
// locale1 and never set optimistically. That is what makes a refused write
// self-evidently a no-op — the check stays where it was — and what makes a
// `localectl` typed into a terminal move the badge with no shell involvement.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/keyboard/keyboard_config.dart';
import 'package:graceful_shell/keyboard/keyboard_short_codes.dart';
import 'package:graceful_shell/keyboard/keyboard_sources.dart';
import 'package:graceful_shell/keyboard/locale1_client.dart';
import 'package:graceful_shell/keyboard/xkb_catalog.dart';

/// How far along the store's view of locale1 is.
///
/// Deliberately not a `ShellService`/`ServiceStatus`: that pair answers "should
/// I show a spinner?", for which a decline and a success are the same answer,
/// and it would settle `ready` on a machine where every layout change is
/// refused. This is `NotificationDaemonStatus`'s split.
enum KeyboardStatus {
  /// Nothing holds a lease; nothing has been read.
  idle,

  /// The first read is in flight.
  loading,

  /// locale1 answered.
  ready,

  /// locale1 could not be reached at all. The user's own list is still
  /// editable — it is graceful's config, not the machine's.
  unavailable,
}

const List<String> _kSourcesPath = ['keyboard', 'sources'];

class KeyboardStore extends ChangeNotifier {
  KeyboardStore._({
    Locale1Client? client,
    ConfigStore? configStore,
    XkbCatalogReader? catalogReader,
  }) : _client = client ?? DBusLocale1Client(),
       _configStore = configStore,
       _catalogReader = catalogReader ?? XkbCatalogReader.instance;

  static final KeyboardStore instance = KeyboardStore._();

  /// A detached store with an injected client and config, so a widget test can
  /// take a real lease with no system bus and no `/usr/share` behind it.
  @visibleForTesting
  factory KeyboardStore.forTesting({
    required Locale1Client client,
    ConfigStore? configStore,
    XkbCatalogReader? catalogReader,
  }) => KeyboardStore._(
    client: client,
    configStore: configStore,
    catalogReader: catalogReader,
  );

  final Locale1Client _client;
  final ConfigStore? _configStore;
  final XkbCatalogReader _catalogReader;

  ConfigStore? _resolvedConfig;
  bool _configResolved = false;

  /// The config this store reads and writes its source list through, or null.
  ///
  /// Resolved lazily, because `ConfigStore.instance` throws before
  /// `initShared()` and a store constructed at import time must not be the
  /// thing that trips it — and **nullable**, because a module built alone in a
  /// widget test has no `main()` behind it. That is
  /// `ShellServicesScope.isLoading`'s default applied one layer down: with no
  /// shared store the list is whatever [seed] put there and nothing is
  /// persisted, which is exactly what a test wants and is never the shell's
  /// own state.
  ConfigStore? get _config {
    if (_configResolved) return _resolvedConfig;
    _configResolved = true;
    _resolvedConfig = _configStore ?? _sharedConfigOrNull();
    return _resolvedConfig;
  }

  static ConfigStore? _sharedConfigOrNull() {
    try {
      return ConfigStore.instance;
    } catch (_) {
      return null;
    }
  }

  // --- published state -----------------------------------------------------

  List<InputSource> _sources = const [];

  /// The user's ordered input sources, from `[[keyboard.sources]]`.
  List<InputSource> get sources => _sources;

  List<String> _shortCodes = const [];

  /// The badge text for each of [sources], positionally.
  List<String> get shortCodes => _shortCodes;

  Locale1Keyboard? _systemState;

  /// What locale1 last reported, or null before the first read.
  Locale1Keyboard? get systemState => _systemState;

  KeyboardStatus _status = KeyboardStatus.idle;
  KeyboardStatus get status => _status;

  /// Why the last write did not land, or empty.
  ///
  /// Persists until a later [activate] or [retry] succeeds — not cleared by
  /// closing the popup, not by a timer, and not by [release]. Every failure
  /// here is recoverable without restarting the shell (the other session can
  /// gain an agent, the bus can come back) and the shell cannot detect the
  /// recovery, so the retry is the user's to trigger.
  String _error = '';
  String get error => _error;

  Locale1FailureKind? _errorKind;
  Locale1FailureKind? get errorKind => _errorKind;

  InputSource? _pending;

  /// The source a `SetX11Keyboard` is in flight for, or null.
  ///
  /// There is no timeout behind this: the call may be sitting behind a polkit
  /// prompt, which is the user's to answer, and a D-Bus call cannot be
  /// withdrawn anyway.
  InputSource? get pending => _pending;

  XkbCatalog _catalog = XkbCatalog.empty;

  /// The installed layouts and variants. Empty until the lazy read lands, and
  /// legitimately empty forever on a machine with no `xkb-data`.
  XkbCatalog get catalog => _catalog;

  /// Which of [sources] locale1 is applying, or `-1`.
  int get activeIndex {
    final state = _systemState;
    if (state == null) return -1;
    return activeSourceIndex(_sources, state);
  }

  /// The layout locale1 is applying when it is in no source, else null.
  ///
  /// A real state rather than an error: somebody ran `localectl`, or the
  /// machine shipped configured this way. Both surfaces render it — falling
  /// back to source 0 would tell the user they are typing in a layout they are
  /// not.
  InputSource? get unlistedActive {
    final state = _systemState;
    if (state == null) return null;
    if (activeSourceIndex(_sources, state) >= 0) return null;
    return effectiveSource(state);
  }

  /// The active source's badge text, whether it is listed or not.
  String get activeShortCode {
    final index = activeIndex;
    if (index >= 0 && index < _shortCodes.length) return _shortCodes[index];
    final unlisted = unlistedActive;
    return unlisted == null ? '' : shortCodeFor(unlisted.layout);
  }

  String describe(InputSource source) => describeSource(_catalog, source);

  // --- leases --------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<Locale1Keyboard>? _changesSub;
  bool _listeningToConfig = false;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Whether the seed has already been considered. Once per store, not once
  /// per lease: a second lease must not re-seed a list the user has emptied.
  bool _seedChecked = false;

  /// Take a lease.
  ///
  /// Notifies nothing synchronously — this runs inside the acquiring widget's
  /// `initState`, and a `notifyListeners` from there is a `setState` on every
  /// other surface already holding a lease, during a build. `FortuneStore` and
  /// `WeatherStore.refresh` are arranged the same way for the same reason.
  void acquire() {
    _leases++;
    if (_leases > 1) return;

    _readConfig(notify: false);
    final config = _config;
    if (config != null && !_listeningToConfig) {
      _listeningToConfig = true;
      config.addListener(_onConfigChanged);
    }

    _status = KeyboardStatus.loading;
    // Subscribed before the first read, so a read that throws does not also
    // cost the subscription that would have corrected it.
    _changesSub ??= _client.changes.listen(_onSystemState);
    unawaited(_loadCatalog());
    unawaited(_refresh(seed: true));
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    _changesSub?.cancel();
    _changesSub = null;
    if (_listeningToConfig) {
      _listeningToConfig = false;
      _config?.removeListener(_onConfigChanged);
    }
    // `_sources`, `_systemState` and `_error` are deliberately kept: a popup
    // closing must not throw away a failure the user has not read yet.
  }

  // --- reads ---------------------------------------------------------------

  Future<void> _loadCatalog() async {
    final catalog = await _catalogReader.load();
    if (identical(catalog, _catalog)) return;
    _catalog = catalog;
    notifyListeners();
  }

  Future<void> _refresh({bool seed = false}) async {
    try {
      final state = await _client.read();
      _systemState = state;
      _status = KeyboardStatus.ready;
      if (seed) _seedFromSystem(state);
    } on Locale1Failure catch (e) {
      _status = KeyboardStatus.unavailable;
      _error = e.message;
      _errorKind = e.kind;
    } catch (e) {
      _status = KeyboardStatus.unavailable;
      _error = 'The keyboard layout service could not be read.';
      _errorKind = Locale1FailureKind.failed;
      debugPrint('keyboard: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Writes locale1's groups into `[[keyboard.sources]]`, once, when the key is
  /// **absent**.
  ///
  /// This is the one place the Background section's "discovery must not write"
  /// rule is deliberately inverted, and the reason is that there is nothing
  /// left to re-discover: locale1 holds only the active layout, so the first
  /// `SetX11Keyboard` this feature makes destroys the installer-configured list
  /// forever. Present-and-empty is left alone — that is the user having removed
  /// everything.
  void _seedFromSystem(Locale1Keyboard state) {
    if (_seedChecked) return;
    _seedChecked = true;
    final config = _config;
    if (config == null) return;
    if (config.get<List>(_kSourcesPath) != null) return;
    final seeded = seedSourcesFrom(state);
    if (seeded.isEmpty) return;
    _writeSources(seeded);
  }

  void _onSystemState(Locale1Keyboard state) {
    if (_systemState == state) return;
    _systemState = state;
    _status = KeyboardStatus.ready;
    notifyListeners();
  }

  // --- config --------------------------------------------------------------

  String _sourcesSignature = '';

  /// Fires on every keystroke anywhere in the settings UI, so it compares a
  /// signature of its own subtree and early-returns — `DesktopStore`'s rule.
  void _onConfigChanged() => _readConfig();

  void _readConfig({bool notify = true}) {
    final config = _config;
    if (config == null) return;
    final raw = config.get<List>(_kSourcesPath);
    final signature = '$raw';
    if (signature == _sourcesSignature) return;
    _sourcesSignature = signature;
    _sources = KeyboardConfig.parseSources(
      config.getList<Map<String, dynamic>>(_kSourcesPath),
    );
    _shortCodes = assignShortCodes(_sources);
    if (notify) notifyListeners();
  }

  void _writeSources(List<InputSource> next) {
    final config = _config;
    if (config == null) {
      // No shared config (a widget test): keep the edit in memory so the UI
      // under test still behaves, and persist nothing.
      _sources = next;
      _shortCodes = assignShortCodes(next);
      notifyListeners();
      return;
    }
    config.set(_kSourcesPath, [for (final source in next) source.toMap()]);
  }

  /// Appends [source], unless it is already listed.
  void addSource(InputSource source) {
    if (_sources.contains(source)) return;
    _writeSources([..._sources, source]);
  }

  void removeAt(int index) {
    if (index < 0 || index >= _sources.length) return;
    _writeSources([..._sources]..removeAt(index));
  }

  /// Moves the source at [index] by [delta] places.
  void moveBy(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= _sources.length) return;
    if (target < 0 || target >= _sources.length) return;
    final next = [..._sources];
    final held = next[index];
    next[index] = next[target];
    next[target] = held;
    _writeSources(next);
  }

  // --- writes --------------------------------------------------------------

  /// Makes [source] the machine's layout.
  ///
  /// Two rules the implementation carries. It **re-reads before it writes** and
  /// sends `model` and `options` back unchanged — sending `''` for them
  /// silently deletes a user's `compose:ralt` or `caps:escape`, which is
  /// invisible until they reach for the key. And it **refuses to stack**: a
  /// call can be sitting behind a polkit prompt for a minute, and two queued
  /// writes would fight.
  ///
  /// Nothing here moves [activeIndex]. That follows locale1's own
  /// `PropertiesChanged`, which is what makes a denial a visible no-op.
  Future<void> activate(InputSource source) async {
    if (_pending != null) return;
    _pending = source;
    _lastAttempt = source;
    notifyListeners();
    try {
      final current = await _client.read();
      _systemState = current;
      await _client.setKeyboard(
        current.copyWith(layout: source.layout, variant: source.variant),
      );
      _error = '';
      _errorKind = null;
      _status = KeyboardStatus.ready;
      _lastAttempt = null;
      // The reply says the write was accepted, not that it has been applied.
      // Re-read rather than assume: on a machine whose signal never arrives
      // this is what moves the check, and where it does arrive it is the same
      // answer twice.
      unawaited(_refresh());
    } on Locale1Failure catch (e) {
      _error = e.message;
      _errorKind = e.kind;
    } catch (e) {
      _error = 'The keyboard layout could not be changed.';
      _errorKind = Locale1FailureKind.failed;
      debugPrint('keyboard: $e');
    } finally {
      _pending = null;
      notifyListeners();
    }
  }

  /// The source whose activation failed, so [retry] re-issues it rather than
  /// merely re-reading.
  InputSource? _lastAttempt;

  /// Re-runs whatever failed.
  ///
  /// Public because both surfaces offer it: the popup's error strip and the
  /// settings page's banner. Refuses to stack on a call already in flight, for
  /// [activate]'s reason.
  Future<void> retry() async {
    if (_pending != null) return;
    final attempt = _lastAttempt;
    if (attempt != null) return activate(attempt);
    _error = '';
    _errorKind = null;
    _status = KeyboardStatus.loading;
    notifyListeners();
    await _refresh();
  }

  /// Seeds a store for a widget test, with no client behind it.
  @visibleForTesting
  void seed({
    List<InputSource>? sources,
    Locale1Keyboard? systemState,
    KeyboardStatus? status,
    String? error,
    Locale1FailureKind? errorKind,
    InputSource? pending,
    XkbCatalog? catalog,
  }) {
    if (sources != null) {
      _sources = sources;
      _shortCodes = assignShortCodes(sources);
    }
    if (systemState != null) _systemState = systemState;
    if (status != null) _status = status;
    if (error != null) _error = error;
    if (errorKind != null) _errorKind = errorKind;
    _pending = pending;
    if (catalog != null) _catalog = catalog;
    notifyListeners();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _changesSub = null;
    if (_listeningToConfig) {
      _listeningToConfig = false;
      _config?.removeListener(_onConfigChanged);
    }
    super.dispose();
  }
}
