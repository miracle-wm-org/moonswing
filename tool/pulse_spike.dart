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
//
// It also reports default-device moves, which arrive on PulseAudio's *server*
// facility and on no other. That half is worth exercising here for the same
// reason as the rest: the shell filters every level event against a device
// name, so a server event that never arrives does not look like a bug in the
// event path — it looks like the volume module and the OSD quietly deciding to
// stop reporting, from the moment the user picks another output. Switch the
// default while this runs:
//
//   pactl set-default-sink <name>   # `pactl list short sinks` for the names

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
  var serverEvents = 0;

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

  client.onServerChanged.listen((info) {
    serverEvents++;
    stdout.writeln('server  default sink=${info.defaultSinkName} '
        'source=${info.defaultSourceName}');
  });

  final info = await client.getServerInfo();
  stdout.writeln('default sink   ${info.defaultSinkName}');
  stdout.writeln('default source ${info.defaultSourceName}');
  stdout.writeln('watching for ${seconds}s — change the volume from elsewhere, '
      'and switch the default device');

  await Future<void>.delayed(Duration(seconds: seconds));
  stdout.writeln('sink events: $sinkEvents  source events: $sourceEvents  '
      'server events: $serverEvents');

  client.dispose();
  exit(sinkEvents > 0 ? 0 : 1);
}
