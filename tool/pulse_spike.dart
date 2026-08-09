// Standalone harness for the PulseAudio client's event path.
//
// `lib/pulse_client.dart` imports no Flutter, for the same reason the
// screencast stack does not: it lets the whole subscribe -> dispatch -> stream
// chain be exercised against the real server with no engine to draw with. That
// matters here because the bug this was written for only appears when *nothing
// else* is in flight — a change made through the client drives the mainloop by
// a different path and always worked.
//
//   dart run tool/pulse_spike.dart [seconds]
//   GRACEFUL_PULSE_LOG=1 dart run tool/pulse_spike.dart
//
// While it runs, change the volume from somewhere else — the keyboard's knob,
// or `pactl set-sink-volume @DEFAULT_SINK@ +5%`. Exits non-zero if nothing
// arrived.

import 'dart:async';
import 'dart:io';

import 'package:graceful_shell/pulse_client.dart';

Future<void> main(List<String> args) async {
  final seconds = args.isEmpty ? 15 : int.parse(args.first);

  final client = PulseClient();
  await client.initialize();
  stdout.writeln('connected');

  var sinkEvents = 0;
  var sourceEvents = 0;

  client.onSinkChanged.listen((s) {
    sinkEvents++;
    stdout.writeln('sink    ${s.name} '
        'vol=${(s.volume * 100).round()}% mute=${s.mute}');
  });
  client.onSourceChanged.listen((s) {
    sourceEvents++;
    stdout.writeln('source  ${s.name} '
        'vol=${(s.volume * 100).round()}% mute=${s.mute}');
  });

  final info = await client.getServerInfo();
  stdout.writeln('default sink   ${info.defaultSinkName}');
  stdout.writeln('default source ${info.defaultSourceName}');
  stdout.writeln('watching for ${seconds}s — change the volume from elsewhere');

  await Future<void>.delayed(Duration(seconds: seconds));
  stdout.writeln('sink events: $sinkEvents  source events: $sourceEvents');

  client.dispose();
  exit(sinkEvents > 0 ? 0 : 1);
}
