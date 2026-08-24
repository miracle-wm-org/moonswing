// The OSD's default-device bookkeeping.
//
// `startOsdService` owns a real `PulseClient` — a live server connection in
// its own isolate — so the decision it makes on every audio event is only
// reachable from a test through `OsdAudioTracker`, which is why that type
// exists. What is pinned here is mostly the *silences*: a card that appears
// for state the shell merely discovered is as wrong as one that never appears
// at all, and the two failure modes trade off against each other.

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/osd/osd_audio_tracker.dart';
import 'package:graceful_shell/pulse_client.dart';

PaSink _sink(String name, double volume, {bool mute = false}) => PaSink(
      index: 0,
      name: name,
      description: name,
      mute: mute,
      volume: volume,
      channelCount: 2,
      balance: 0.0,
    );

PaSource _source(String name, double volume, {bool mute = false}) => PaSource(
      index: 0,
      name: name,
      description: name,
      mute: mute,
      volume: volume,
    );

PaServerInfo _server(String sink, String source) =>
    PaServerInfo(defaultSinkName: sink, defaultSourceName: source);

void main() {
  group('OsdAudioTracker', () {
    test('drops everything until it has been seeded', () {
      final tracker = OsdAudioTracker();
      expect(tracker.defaultSink, isEmpty);
      expect(tracker.observeSink(_sink('speakers', 0.4)), isFalse);
      expect(tracker.observeSource(_source('mic', 0.4)), isFalse);
    });

    test('ignores devices that are not the default ones', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4), _sink('headset', 0.9)],
          sources: [_source('mic', 0.5)],
        );

      expect(tracker.observeSink(_sink('headset', 0.1)), isFalse);
      expect(tracker.observeSource(_source('webcam', 0.1)), isFalse);
    });

    test('stays quiet for an event that moved neither volume nor mute', () {
      // PulseAudio emits sink events for a stream connecting or a port switch;
      // none of those is a level change and none should raise the card.
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5)],
        );

      expect(tracker.observeSink(_sink('speakers', 0.4)), isFalse);
      expect(tracker.observeSource(_source('mic', 0.5)), isFalse);
    });

    test('reports a volume move and a mute move on the default devices', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5)],
        );

      expect(tracker.observeSink(_sink('speakers', 0.6)), isTrue);
      expect(tracker.observeSink(_sink('speakers', 0.6, mute: true)), isTrue);
      // The move is banked, so repeating it is not a second change.
      expect(tracker.observeSink(_sink('speakers', 0.6, mute: true)), isFalse);

      expect(tracker.observeSource(_source('mic', 0.5, mute: true)), isTrue);
      expect(tracker.observeSource(_source('mic', 0.5, mute: true)), isFalse);
    });

    // The bug this whole change exists for: a default-device switch is
    // reported on PulseAudio's server facility and nowhere else, so a tracker
    // that never re-seeds goes on filtering every event against the device the
    // user has left.
    test('follows the default sink to another device', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4), _sink('headset', 0.9)],
          sources: [_source('mic', 0.5)],
        );

      // Before the switch the headset is somebody else's device.
      expect(tracker.observeSink(_sink('headset', 0.8)), isFalse);

      tracker.seed(
        server: _server('headset', 'mic'),
        sinks: [_sink('speakers', 0.4), _sink('headset', 0.9)],
        sources: [_source('mic', 0.5)],
      );

      expect(tracker.defaultSink, 'headset');
      // Adopting it is not a change the user made, so it raises nothing...
      expect(tracker.observeSink(_sink('headset', 0.9)), isFalse);
      // ...but turning it up is, which is what used to be dropped forever.
      expect(tracker.observeSink(_sink('headset', 0.7)), isTrue);
      // And the device that was left has stopped speaking for the indicator.
      expect(tracker.observeSink(_sink('speakers', 0.1)), isFalse);
    });

    test('follows the default source too', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5), _source('headset-mic', 0.3)],
        );

      tracker.seed(
        server: _server('speakers', 'headset-mic'),
        sinks: [_sink('speakers', 0.4)],
        sources: [_source('mic', 0.5), _source('headset-mic', 0.3)],
      );

      expect(tracker.defaultSource, 'headset-mic');
      expect(tracker.observeSource(_source('headset-mic', 0.6)), isTrue);
      expect(tracker.observeSource(_source('mic', 0.9)), isFalse);
    });

    // Re-seeding costs three round trips to the server, and PulseAudio emits
    // server events for more than a device move.
    test('defaultsMoved only answers true when a name actually changed', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5)],
        );

      expect(tracker.defaultsMoved(_server('speakers', 'mic')), isFalse);
      expect(tracker.defaultsMoved(_server('headset', 'mic')), isTrue);
      expect(tracker.defaultsMoved(_server('speakers', 'headset-mic')), isTrue);
      // No default at all — every sink was just unplugged.
      expect(tracker.defaultsMoved(_server('', '')), isTrue);
    });

    // The seed's names and levels have to land together. The service reaches
    // `seed` after three awaits, and a level event arriving between them used
    // to be measured against the *other* device's baseline.
    test('a device missing from the list leaves no stale baseline', () {
      final tracker = OsdAudioTracker()
        ..seed(
          server: _server('speakers', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5)],
        )
        // The new default has not appeared in the sink list yet.
        ..seed(
          server: _server('headset', 'mic'),
          sinks: [_sink('speakers', 0.4)],
          sources: [_source('mic', 0.5)],
        );

      // 0.4 was the *speakers'* level. Matching the headset against it would
      // silence a real change; treating it as a change would flash a card for
      // a level nobody touched. It is the first sighting, so: quiet, banked.
      expect(tracker.observeSink(_sink('headset', 0.4)), isFalse);
      expect(tracker.observeSink(_sink('headset', 0.5)), isTrue);
    });
  });
}
