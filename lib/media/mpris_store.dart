// The MPRIS client: what is playing, on which player, and the four transport
// controls.
//
// Flutter-free apart from [ChangeNotifier], so the bar module and the desktop
// widget can both consume it and neither owns it. It was the bar module: every
// field below lived in `MediaPlayerState`, which meant a second consumer would
// have meant a second D-Bus connection, a second `listNames()` walk and a second
// subscription per player.

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// Every MPRIS player owns a bus name under this prefix.
const String kMprisPrefix = 'org.mpris.MediaPlayer2.';
const String kMprisPlayerInterface = 'org.mpris.MediaPlayer2.Player';
const String kMprisPath = '/org/mpris/MediaPlayer2';

/// The `PlaybackStatus` property, as an enum rather than the raw string.
enum MprisPlaybackStatus {
  playing,
  paused,
  stopped;

  static MprisPlaybackStatus fromString(String value) => switch (value) {
        'Playing' => MprisPlaybackStatus.playing,
        'Paused' => MprisPlaybackStatus.paused,
        _ => MprisPlaybackStatus.stopped,
      };
}

/// One player's published state.
///
/// Mutable and mutated in place by [MprisStore], which is the only thing that
/// may: consumers read it and are told to rebuild by the store's notification.
class MprisPlayer {
  MprisPlayer({required this.busName});

  final String busName;

  MprisPlaybackStatus status = MprisPlaybackStatus.stopped;
  String title = '';
  String artist = '';
  String album = '';

  /// `mpris:artUrl`, verbatim. Usually a `file:` URI; Spotify and some web
  /// players publish an `https:` one, which [artFile] declines rather than
  /// fetching — the shell does no network I/O to draw a desktop widget.
  String artUrl = '';

  bool canPlay = false;
  bool canPause = false;
  bool canGoNext = false;
  bool canGoPrevious = false;
  bool canControl = false;

  /// `mpris:length`, or null when the player does not publish one (a live
  /// stream, and most web players).
  Duration? length;

  /// The last `Position` read, and when it was read.
  ///
  /// Progress is *derived* from the pair rather than accumulated, the rule
  /// `lib/timers/` documents: a ticker that added its own period would drift by
  /// however late each wakeup was, and would lose the whole of a suspend.
  Duration position = Duration.zero;
  DateTime? positionAt;

  /// The player's own name, from its bus name — `spotify`, `vlc`, `firefox`.
  /// The fallback label when a player publishes no metadata at all.
  String get identity {
    final tail = busName.startsWith(kMprisPrefix)
        ? busName.substring(kMprisPrefix.length)
        : busName;
    // `org.mpris.MediaPlayer2.firefox.instance_1_23` — the instance suffix is
    // bookkeeping, not a name.
    final dot = tail.indexOf('.');
    return dot < 0 ? tail : tail.substring(0, dot);
  }

  bool get isPlaying => status == MprisPlaybackStatus.playing;

  /// The album art as a local file, or null when there is none, it is not a
  /// local file, or it has been deleted (players routinely publish art in
  /// `/tmp`, which a reboot takes with it).
  File? get artFile {
    if (!artUrl.startsWith('file://')) return null;
    final uri = Uri.tryParse(artUrl);
    if (uri == null) return null;
    final file = File(uri.toFilePath());
    return file.existsSync() ? file : null;
  }

  /// "Artist — Title", or whichever half exists, or the player's identity.
  String get displayText {
    if (title.isEmpty && artist.isEmpty) return identity;
    if (artist.isEmpty) return title;
    if (title.isEmpty) return artist;
    return '$artist — $title';
  }
}

/// What is playing on this machine, and the controls for it.
///
/// The singleton-[ChangeNotifier]-with-leases shape: the D-Bus connection and
/// every per-player subscription exist only while somebody holds a lease, and a
/// *detail* lease adds the one-second `Position` poll a progress bar needs and a
/// bar module does not. Before this there was one connection per bar per monitor.
class MprisStore extends ChangeNotifier {
  MprisStore._();

  static final MprisStore instance = MprisStore._();

  /// A detached, **offline** store: it never opens a bus, so a lease taken by
  /// a widget under test cannot reach for a session bus that a test runner does
  /// not have. Feed it with [seed].
  @visibleForTesting
  factory MprisStore.forTesting() => MprisStore._().._offline = true;

  /// The wall clock, injectable so a test can make progress interpolation
  /// deterministic.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  DBusClient? _dbus;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;
  final Map<String, StreamSubscription<DBusPropertiesChangedSignal>> _propSubs =
      {};
  final Map<String, MprisPlayer> _players = {};

  MprisPlayer? _active;
  bool _offline = false;
  int _leases = 0;
  int _detailLeases = 0;
  Timer? _positionTimer;
  bool _disposed = false;

  /// The player the UI speaks for: the one that is playing, else one that is
  /// paused, else none.
  MprisPlayer? get active => _active;

  /// Every known player, playing or not. Nothing renders this yet; it is what a
  /// future "switch player" control reads.
  List<MprisPlayer> get players => List.unmodifiable(_players.values);

  bool get hasPlayer => _active != null;

  /// [MprisPlayer.position], carried forward to now while playing.
  ///
  /// Clamped to the track length: a `Position` read a moment before a track
  /// change would otherwise run past the end of the bar it is drawing.
  Duration get position {
    final player = _active;
    if (player == null) return Duration.zero;
    var value = player.position;
    final at = player.positionAt;
    if (player.isPlaying && at != null) {
      final elapsed = now().difference(at);
      // A backwards clock step (NTP, a resumed laptop) is dropped rather than
      // subtracted, so the readout can stall but never runs backwards.
      if (elapsed > Duration.zero) value += elapsed;
    }
    final length = player.length;
    if (length != null && value > length) return length;
    return value;
  }

  /// Progress through the track in 0..1, or null when the length is unknown —
  /// which a progress bar has to render as "no bar", not as zero.
  double? get progress {
    final length = _active?.length;
    if (length == null || length <= Duration.zero) return null;
    return (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Leases
  // ---------------------------------------------------------------------------

  /// Takes a lease. The first one connects to the session bus and enumerates
  /// the players; a [detailed] lease additionally polls `Position` once a
  /// second, which only a widget drawing progress needs.
  void acquire({bool detailed = false}) {
    _leases++;
    if (detailed) {
      _detailLeases++;
      _syncPositionTimer();
    }
    if (_leases == 1) unawaited(_connect());
  }

  void release({bool detailed = false}) {
    if (detailed && _detailLeases > 0) {
      _detailLeases--;
      _syncPositionTimer();
    }
    if (_leases > 0) _leases--;
    if (_leases == 0) _disconnect();
  }

  /// Seeds the store with players and no D-Bus behind it, for widget tests.
  @visibleForTesting
  void seed(List<MprisPlayer> players) {
    _players
      ..clear()
      ..addEntries([
        for (final player in players) MapEntry(player.busName, player),
      ]);
    _selectActive();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  Future<void> playPause() => _call('PlayPause');
  Future<void> next() => _call('Next');
  Future<void> previous() => _call('Previous');
  Future<void> stop() => _call('Stop');

  Future<void> _call(String method) async {
    final player = _active;
    final dbus = _dbus;
    if (player == null || dbus == null) return;
    try {
      final object = DBusRemoteObject(
        dbus,
        name: player.busName,
        path: DBusObjectPath(kMprisPath),
      );
      await object.callMethod(kMprisPlayerInterface, method, []);
    } catch (_) {
      // The player vanished mid-click, or refused. Its own properties-changed
      // signal (or nameOwnerChanged) is what corrects the UI; there is nothing
      // useful to show for a transport button that did not land.
    }
  }

  // ---------------------------------------------------------------------------
  // D-Bus
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_offline || _dbus != null) return;
    try {
      final dbus = DBusClient.session();
      _dbus = dbus;
      _nameOwnerSub = dbus.nameOwnerChanged.listen(_onNameOwnerChanged);
      final names = await dbus.listNames();
      // The lease may have been dropped while `listNames` was in flight.
      if (_dbus != dbus) return;
      for (final name in names) {
        if (name.startsWith(kMprisPrefix)) await _addPlayer(name);
      }
    } catch (_) {
      // No session bus: the store stays empty and every consumer renders its
      // "nothing playing" state. This is a graceful decline, not a failure.
    }
  }

  void _disconnect() {
    _nameOwnerSub?.cancel();
    _nameOwnerSub = null;
    for (final sub in _propSubs.values) {
      sub.cancel();
    }
    _propSubs.clear();
    _players.clear();
    _active = null;
    _positionTimer?.cancel();
    _positionTimer = null;
    _dbus?.close();
    _dbus = null;
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (!event.name.startsWith(kMprisPrefix)) return;
    final owner = event.newOwner;
    if (owner != null && owner.isNotEmpty) {
      unawaited(_addPlayer(event.name));
    } else {
      _removePlayer(event.name);
    }
  }

  Future<void> _addPlayer(String busName) async {
    final dbus = _dbus;
    if (dbus == null || _players.containsKey(busName)) return;

    final player = MprisPlayer(busName: busName);
    _players[busName] = player;

    final object = DBusRemoteObject(
      dbus,
      name: busName,
      path: DBusObjectPath(kMprisPath),
    );

    try {
      _applyProperties(
        player,
        await object.getAllProperties(kMprisPlayerInterface),
      );
    } catch (_) {
      // Gone before we could ask.
      _players.remove(busName);
      return;
    }

    _propSubs[busName] = object.propertiesChanged.listen((signal) {
      if (signal.propertiesInterface != kMprisPlayerInterface) return;
      _applyProperties(player, signal.changedProperties);
      // A player that starts playing takes over, and one that stops hands back
      // — both are the same re-selection.
      _selectActive();
      _syncPositionTimer();
      notifyListeners();
    });

    _selectActive();
    _syncPositionTimer();
    notifyListeners();
  }

  void _removePlayer(String busName) {
    _propSubs.remove(busName)?.cancel();
    _players.remove(busName);
    _selectActive();
    _syncPositionTimer();
    notifyListeners();
  }

  void _applyProperties(MprisPlayer player, Map<String, DBusValue> props) {
    final status = props['PlaybackStatus'];
    if (status is DBusString) {
      player.status = MprisPlaybackStatus.fromString(status.value);
      // A play/pause resets the reference point the interpolation runs from,
      // or resuming would count the paused seconds as elapsed.
      player.positionAt = now();
    }
    final metadata = props['Metadata'];
    if (metadata != null) _applyMetadata(player, metadata);

    bool? boolean(String key) {
      final value = props[key];
      return value is DBusBoolean ? value.value : null;
    }

    player.canPlay = boolean('CanPlay') ?? player.canPlay;
    player.canPause = boolean('CanPause') ?? player.canPause;
    player.canGoNext = boolean('CanGoNext') ?? player.canGoNext;
    player.canGoPrevious = boolean('CanGoPrevious') ?? player.canGoPrevious;
    player.canControl = boolean('CanControl') ?? player.canControl;

    // `Position` is deliberately **not** in PropertiesChanged per the MPRIS
    // spec (it would be a signal per second), so this only ever arrives from
    // the explicit read in [_pollPosition].
    final position = props['Position'];
    if (position is DBusInt64) {
      player.position = Duration(microseconds: position.value);
      player.positionAt = now();
    }
  }

  void _applyMetadata(MprisPlayer player, DBusValue value) {
    if (value is! DBusDict) return;
    final metadata = <String, DBusValue>{};
    for (final entry in value.children.entries) {
      final key = entry.key;
      final child = entry.value;
      if (key is! DBusString) continue;
      metadata[key.value] = child is DBusVariant ? child.value : child;
    }

    final title = metadata['xesam:title'];
    player.title = title is DBusString ? title.value : '';

    final album = metadata['xesam:album'];
    player.album = album is DBusString ? album.value : '';

    final artist = metadata['xesam:artist'];
    player.artist = artist is DBusArray
        ? artist.children.whereType<DBusString>().map((s) => s.value).join(', ')
        : artist is DBusString
            ? artist.value
            : '';

    final art = metadata['mpris:artUrl'];
    player.artUrl = art is DBusString ? art.value : '';

    final length = metadata['mpris:length'];
    // Length is `x` (int64) per the spec, but players publish `t` and even a
    // double; a wrongly-typed one costs the progress bar, never the widget.
    final micros = switch (length) {
      DBusInt64() => length.value,
      DBusUint64() => length.value,
      DBusDouble() => length.value.toInt(),
      _ => null,
    };
    player.length = micros != null && micros > 0
        ? Duration(microseconds: micros)
        : null;

    // A new track starts where its metadata says, not where the last one had
    // got to. Without this the progress bar of a just-started track shows the
    // previous track's elapsed time until the next poll lands.
    player.position = Duration.zero;
    player.positionAt = now();
  }

  /// Picks the player the UI speaks for: the current one while it is still
  /// playing, else any player that is, else any that is paused.
  void _selectActive() {
    final current = _active;
    if (current != null &&
        _players.containsKey(current.busName) &&
        current.isPlaying) {
      return;
    }
    for (final player in _players.values) {
      if (player.isPlaying) {
        _active = player;
        return;
      }
    }
    for (final player in _players.values) {
      if (player.status == MprisPlaybackStatus.paused) {
        _active = player;
        return;
      }
    }
    _active = null;
  }

  /// The `Position` poll runs only while a detail lease is held *and* something
  /// is actually playing — `SystemStatsStore`'s rule, so an idle shell with the
  /// desktop widget on screen wakes for this exactly never.
  void _syncPositionTimer() {
    final wanted = _detailLeases > 0 && (_active?.isPlaying ?? false);
    if (wanted == (_positionTimer != null)) return;
    if (!wanted) {
      _positionTimer?.cancel();
      _positionTimer = null;
      return;
    }
    _positionTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollPosition());
    _pollPosition();
  }

  Future<void> _pollPosition() async {
    final player = _active;
    final dbus = _dbus;
    if (player == null || dbus == null) return;
    try {
      final object = DBusRemoteObject(
        dbus,
        name: player.busName,
        path: DBusObjectPath(kMprisPath),
      );
      final value =
          await object.getProperty(kMprisPlayerInterface, 'Position');
      if (value is! DBusInt64) return;
      player.position = Duration(microseconds: value.value);
      player.positionAt = now();
      notifyListeners();
    } catch (_) {
      // Players are allowed to refuse Position (and several do). The bar is
      // interpolated from the last good read either way.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnect();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
