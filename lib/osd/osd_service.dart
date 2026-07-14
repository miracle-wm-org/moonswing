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
/// Like the other `start*Service` functions this swallows its failures: a
/// machine with no PulseAudio or no backlight loses the indicator, not the
/// shell.
Future<void> startOsdService(OsdConfig config) async {
  if (!config.enabled) return;
  OsdStore.instance.hideDelay = Duration(milliseconds: config.hideDelayMs);

  _startBrightness();
  await _startAudio();
}

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

Future<void> _startAudio() async {
  try {
    final client = PulseClient();
    await client.initialize();

    final server = await client.getServerInfo();
    var defaultSink = server.defaultSinkName;
    var defaultSource = server.defaultSourceName;

    // Seed the last-known levels so the shell does not flash an indicator for
    // the state it merely discovered at start-up.
    double? lastSinkVolume;
    bool? lastSinkMute;
    for (final sink in await client.getSinkList()) {
      if (sink.name == defaultSink) {
        lastSinkVolume = sink.volume;
        lastSinkMute = sink.mute;
      }
    }

    double? lastSourceVolume;
    bool? lastSourceMute;
    for (final source in await client.getSourceList()) {
      if (source.name == defaultSource) {
        lastSourceVolume = source.volume;
        lastSourceMute = source.mute;
      }
    }

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

    // The default device can move under us (a headset is plugged in, or the
    // user picks another output in settings). Re-resolve it when a device goes
    // away, and re-seed so the switch itself does not raise an indicator.
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

    client.onSinkRemoved.listen((_) => refreshDefaults());
    client.onSourceRemoved.listen((_) => refreshDefaults());
  } catch (e) {
    debugPrint('Audio indicator unavailable: $e');
  }
}
