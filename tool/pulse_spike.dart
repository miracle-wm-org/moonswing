// Standalone harness for the PulseAudio client's event path.
//
// `lib/pulse_client.dart` imports no Flutter, which lets the whole subscribe →
// dispatch → stream chain be exercised against the real server with no engine to
// draw with. That matters because the bug this was written for only appears when
// *nothing else* is in flight — a change made through the client drives the
// mainloop by a different path and always worked.
//
//   dart run tool/pulse_spike.dart [seconds]
//   MOONSWING_PULSE_LOG=1 dart run tool/pulse_spike.dart
//
// While it runs, change the volume from somewhere else — the keyboard's knob, or
// `pactl set-sink-volume @DEFAULT_SINK@ +5%`. Exits non-zero if nothing arrived.
//
// It also reports default-device moves, which arrive on PulseAudio's *server*
// facility and no other. The shell filters every level event against a device
// name, so a server event that never arrives does not look like a bug in the
// event path — it looks like the volume module and the OSD quietly deciding to
// stop reporting. Switch the default while this runs:
//
//   pactl set-default-sink <name>   # `pactl list short sinks` for the names
//
// And it is the regression check for surviving a server restart, the one failure
// a widget test cannot reach. `--reconnect` demands both halves: that a reconnect
// happened at all, and that events still arrive *afterwards* — the second is what
// separates a live process from a merely surviving one.
//
//   dart run tool/pulse_spike.dart --reconnect 60
//   # while it runs, in another terminal:
//   systemctl --user restart pipewire-pulse
//   pactl set-sink-volume @DEFAULT_SINK@ +5%

import 'dart:async';
import 'dart:io';

import 'package:moonswing/pulse_client.dart';

Future<void> main(List<String> args) async {
  final rest = args.where((a) => a != '--reconnect').toList();
  final requireReconnect = args.contains('--reconnect');
  final seconds = rest.isEmpty ? 15 : int.parse(rest.first);

  final client = PulseClient();
  await client.initialize();
  stdout.writeln('connected');

  var sinkEvents = 0;
  var sourceEvents = 0;
  var serverEvents = 0;
  var reconnects = 0;

  // Counted separately, and reset by each reconnect: the question `--reconnect`
  // asks is not whether the client survived but whether it is still listening.
  var eventsSinceReconnect = 0;

  client.onReconnected.listen((_) {
    reconnects++;
    eventsSinceReconnect = 0;
    stdout.writeln('reconnect');
  });

  client.onSinkChanged.listen((s) {
    sinkEvents++;
    eventsSinceReconnect++;
    stdout.writeln('sink    ${s.name} '
        'vol=${(s.volume * 100).round()}% mute=${s.mute}');
  });
  client.onSourceChanged.listen((s) {
    sourceEvents++;
    eventsSinceReconnect++;
    stdout.writeln('source  ${s.name} '
        'vol=${(s.volume * 100).round()}% mute=${s.mute}');
  });

  client.onServerChanged.listen((info) {
    serverEvents++;
    stdout.writeln('server  default sink=${info.defaultSinkName} '
        'source=${info.defaultSourceName}');
  });

  final info = await client.getServerInfo();
  stdout.writeln('default sink   ${info.defaultSinkName}');
  stdout.writeln('default source ${info.defaultSourceName}');
  stdout.writeln(requireReconnect
      ? 'watching for ${seconds}s — restart the audio server, then change the '
          'volume from elsewhere'
      : 'watching for ${seconds}s — change the volume from elsewhere, '
          'and switch the default device');

  await Future<void>.delayed(Duration(seconds: seconds));
  stdout.writeln('sink events: $sinkEvents  source events: $sourceEvents  '
      'server events: $serverEvents  reconnects: $reconnects');

  client.dispose();

  if (requireReconnect) {
    if (reconnects == 0) {
      stderr.writeln('no reconnect seen — was the server restarted?');
      exit(1);
    }
    if (eventsSinceReconnect == 0) {
      stderr.writeln('reconnected, but nothing arrived afterwards');
      exit(1);
    }
    exit(0);
  }
  exit(sinkEvents > 0 ? 0 : 1);
}
