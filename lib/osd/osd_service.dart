import 'package:flutter/foundation.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/osd/brightness_monitor.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/pulse_client.dart';

/// Feeds [OsdStore] from the things the indicator reports on: the default
/// PulseAudio sink and source, and the display backlight.
///
/// The shell only *observes* here — whatever already applies the change
/// (compositor keybindings, the shell's own volume slider) keeps doing so.
///
/// The indicator being off in `config.toml` is a graceful decline: log and
/// return, nothing to wait for. A PulseAudio client that cannot come up
/// throws, and `ShellServices.run` records the service as failed — the enum
/// value is `audio`, and audio is the one capability this service cannot be
/// said to have started without. A missing backlight stays soft on purpose:
/// an empty `/sys/class/backlight` is the normal state of every desktop
/// machine, not a failure, and [BrightnessMonitor.start] is built to go
/// silent there.
Future<void> startOsdService(OsdConfig config) async {
  if (!config.enabled) {
    debugPrint('OSD disabled in config; indicator not started');
    return;
  }
  OsdStore.instance.hideDelay = Duration(milliseconds: config.hideDelayMs);

  _startBrightness();
  await _startAudio();
}

/// No backlight, or no udev to watch it with, is a decline, never a failure —
/// [BrightnessMonitor] already returns silently in both cases, and this guard
/// only keeps an unforeseen throw from taking the audio half down with it.
void _startBrightness() {
  try {
    final monitor = BrightnessMonitor()..start();
    monitor.onChanged.listen(
      (level) => OsdStore.instance.show(OsdKind.brightness, level),
    );
  } catch (e) {
    debugPrint('Brightness indicator unavailable: $e');
  }
}

/// Throws when [PulseClient.initialize] fails — no server to observe means no
/// volume indicator. The `refreshDefaults` guard below is different: it is
/// runtime resilience against a query failing mid-session, after the
/// subscription (the part that matters) is already live.
Future<void> _startAudio() async {
  final client = PulseClient();
  await client.initialize();

  var defaultSink = '';
  var defaultSource = '';

  // Last-known levels, so the shell does not flash an indicator for state it
  // merely discovered — at start-up, or when the default device moves.
  double? lastSinkVolume;
  bool? lastSinkMute;
  double? lastSourceVolume;
  bool? lastSourceMute;

  // Re-resolve the default devices and re-seed. This is both the start-up
  // seeding and the answer to a device going away (a headset is unplugged, or
  // the user picks another output in settings) — the same work either way.
  Future<void> refreshDefaults() async {
    try {
      final info = await client.getServerInfo();
      defaultSink = info.defaultSinkName;
      defaultSource = info.defaultSourceName;
      for (final sink in await client.getSinkList()) {
        if (sink.name == defaultSink) {
          lastSinkVolume = sink.volume;
          lastSinkMute = sink.mute;
        }
      }
      for (final source in await client.getSourceList()) {
        if (source.name == defaultSource) {
          lastSourceVolume = source.volume;
          lastSourceMute = source.mute;
        }
      }
    } catch (e) {
      debugPrint('Could not refresh default audio devices: $e');
    }
  }

  // Subscribe before the first query, never after. These handlers are the
  // only thing that ever raises the volume indicator, and a query that throws
  // or never answers would otherwise cost the shell its subscription for the
  // rest of the session. Until `refreshDefaults` lands, `defaultSink` is
  // empty and the events are simply dropped.
  //
  // PulseAudio emits a sink/source change event for plenty of reasons that
  // have nothing to do with the level (a stream connecting, a port switch),
  // so only an actual move in volume or mute raises the indicator.
  client.onSinkChanged.listen((sink) {
    if (sink.name != defaultSink) return;
    if (sink.volume == lastSinkVolume && sink.mute == lastSinkMute) return;
    lastSinkVolume = sink.volume;
    lastSinkMute = sink.mute;
    OsdStore.instance.show(OsdKind.volume, sink.volume, muted: sink.mute);
  });

  client.onSourceChanged.listen((source) {
    if (source.name != defaultSource) return;
    if (source.volume == lastSourceVolume && source.mute == lastSourceMute) {
      return;
    }
    lastSourceVolume = source.volume;
    lastSourceMute = source.mute;
    OsdStore.instance
        .show(OsdKind.microphone, source.volume, muted: source.mute);
  });

  client.onSinkRemoved.listen((_) => refreshDefaults());
  client.onSourceRemoved.listen((_) => refreshDefaults());

  await refreshDefaults();
}
