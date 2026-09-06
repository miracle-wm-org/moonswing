import 'package:flutter/foundation.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/osd/brightness_monitor.dart';
import 'package:graceful_shell/osd/osd_audio_tracker.dart';
import 'package:graceful_shell/osd/osd_store.dart';
import 'package:graceful_shell/pulse_client.dart';

/// Feeds [OsdStore] from the things the indicator reports on: the default
/// PulseAudio sink and source, and the display backlight.
///
/// The shell only *observes* here — whatever already applies the change keeps
/// doing so.
///
/// The indicator being off in `config.toml` is a graceful decline. A PulseAudio
/// client that cannot come up throws, and `ShellServices.run` records the service
/// as failed. A missing backlight stays soft on purpose: an empty
/// `/sys/class/backlight` is the normal state of every desktop machine.
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

  // Which devices are the default ones, and what level each was last seen at.
  // See [OsdAudioTracker] for why that is one object rather than four
  // variables, and for the rules it applies.
  final tracker = OsdAudioTracker();

  // Re-seeding is three awaited queries, and the events that trigger one can
  // arrive faster than it completes — unplugging a dock moves the default sink
  // and source in quick succession. Without this the older refresh's answer could
  // land last and reinstate the device that has already been left.
  var generation = 0;

  // Re-resolve the default devices and re-seed. This is the start-up seeding,
  // the answer to a device going away (a headset is unplugged), and the answer
  // to the user picking another device in settings — the same work each time.
  Future<void> refreshDefaults() async {
    final mine = ++generation;
    try {
      final server = await client.getServerInfo();
      final sinks = await client.getSinkList();
      final sources = await client.getSourceList();
      if (mine != generation) return;
      tracker.seed(server: server, sinks: sinks, sources: sources);
    } catch (e) {
      debugPrint('Could not refresh default audio devices: $e');
    }
  }

  // Subscribe before the first query, never after. These handlers are the only
  // thing that raises the volume indicator, and a query that throws or never
  // answers would otherwise cost the shell its subscription for the session.
  // Until the first `refreshDefaults` lands the tracker holds no device name and
  // the events are simply dropped.
  client.onSinkChanged.listen((sink) {
    if (!tracker.observeSink(sink)) return;
    OsdStore.instance.show(OsdKind.volume, sink.volume, muted: sink.mute);
  });

  client.onSourceChanged.listen((source) {
    if (!tracker.observeSource(source)) return;
    OsdStore.instance
        .show(OsdKind.microphone, source.volume, muted: source.mute);
  });

  // A default device moving is reported on PulseAudio's *server* facility and
  // nowhere else: neither the device being left nor the one being adopted emits
  // an event of its own. Without this the tracker goes on matching every event
  // against the name it resolved at start-up, so the card stops appearing the
  // moment the user picks another output — and the device they are actually
  // listening to is the one it has stopped reporting on.
  client.onServerChanged.listen((info) {
    if (!tracker.defaultsMoved(info)) return;
    refreshDefaults();
  });

  client.onSinkRemoved.listen((_) => refreshDefaults());
  client.onSourceRemoved.listen((_) => refreshDefaults());

  // The server itself went away and came back. Unlike a default device moving,
  // that is *not* something `onServerChanged` can report here: the restart
  // usually brings the same device names back, so `defaultsMoved` answers false
  // and the tracker would go on measuring events against baselines taken from the
  // server that died — flashing a card for a change nobody made, or silently
  // dropping one that was. Hence the unconditional seeding; `refreshDefaults`'
  // generation counter handles it landing on one already in flight.
  client.onReconnected.listen((_) => refreshDefaults());

  await refreshDefaults();
}
