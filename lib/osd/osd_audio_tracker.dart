import 'package:moonswing/pulse_client.dart';

/// The OSD's memory of which audio devices are the default ones, and of the level
/// each was last seen at.
///
/// Its own type for two reasons. It decides whether a PulseAudio event is worth
/// raising the indicator for, and [startOsdService] owns a real [PulseClient] —
/// a live server connection in its own isolate — which no test can drive. And it
/// is the piece a default-device switch invalidates: every event is filtered
/// against a device *name*, so the names and the levels have to move together or
/// the filter measures one device's events against another's baseline.
///
/// Flutter-free on purpose, like the rest of the sampling layer.
class OsdAudioTracker {
  var _sink = '';
  var _source = '';
  double? _sinkVolume;
  bool? _sinkMute;
  double? _sourceVolume;
  bool? _sourceMute;

  /// The sink events are being matched against. Empty until the first [seed],
  /// which is what drops the events that arrive before start-up has resolved
  /// the defaults.
  String get defaultSink => _sink;

  /// The source events are being matched against.
  String get defaultSource => _source;

  /// Adopts [server]'s default devices and the level each is at right now.
  ///
  /// Names and levels are committed together, which is the whole point of this
  /// being one call rather than a pair of setters: the caller reaches here after
  /// awaiting several queries, and a level event landing between them would
  /// otherwise be measured against the *other* device's last-known level and
  /// flash the indicator for a change nobody made.
  ///
  /// A default device missing from its list leaves no baseline, which
  /// [observeSink]/[observeSource] treat as "not seen yet".
  void seed({
    required PaServerInfo server,
    required Iterable<PaSink> sinks,
    required Iterable<PaSource> sources,
  }) {
    _sink = server.defaultSinkName;
    _source = server.defaultSourceName;

    _sinkVolume = null;
    _sinkMute = null;
    for (final sink in sinks) {
      if (sink.name != _sink) continue;
      _sinkVolume = sink.volume;
      _sinkMute = sink.mute;
      break;
    }

    _sourceVolume = null;
    _sourceMute = null;
    for (final source in sources) {
      if (source.name != _source) continue;
      _sourceVolume = source.volume;
      _sourceMute = source.mute;
      break;
    }
  }

  /// Whether [info] names devices this tracker is not already following.
  ///
  /// PulseAudio emits a server event for more than a default-device move, and
  /// re-seeding runs three queries, so the ones that changed nothing are dropped
  /// here rather than paid for.
  bool defaultsMoved(PaServerInfo info) =>
      info.defaultSinkName != _sink || info.defaultSourceName != _source;

  /// Records [sink] and answers whether it should raise the indicator.
  ///
  /// PulseAudio emits sink events for plenty of reasons that have nothing to do
  /// with the level — a stream connecting, a port switch — so only an actual move
  /// in volume or mute counts. The first sighting of a device never counts
  /// either: that is state the shell merely *discovered*, and showing a card for
  /// it is how a device switch would flash a level nobody touched.
  bool observeSink(PaSink sink) {
    if (sink.name != _sink) return false;
    final known = _sinkVolume != null && _sinkMute != null;
    final moved = sink.volume != _sinkVolume || sink.mute != _sinkMute;
    _sinkVolume = sink.volume;
    _sinkMute = sink.mute;
    return known && moved;
  }

  /// Records [source] and answers whether it should raise the indicator. The
  /// microphone half of [observeSink]; see there for the rules.
  bool observeSource(PaSource source) {
    if (source.name != _source) return false;
    final known = _sourceVolume != null && _sourceMute != null;
    final moved = source.volume != _sourceVolume || source.mute != _sourceMute;
    _sourceVolume = source.volume;
    _sourceMute = source.mute;
    return known && moved;
  }
}
