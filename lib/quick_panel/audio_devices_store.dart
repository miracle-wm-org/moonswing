// The default output and input for the quick settings panel: which devices
// there are, which one is the default in each direction, and each one's level.
//
// The sound module keeps the default sink's level in its own State, and the
// Audio settings tabs keep theirs — each is one surface's view of one
// direction. The panel needs both directions and the device lists at once, and
// it is a popup per bar per monitor, so this is the store-with-leases shape:
// the first lease subscribes to PulseAudio, the last one drops the
// subscriptions, and what was read stays on screen for the next lease.
//
// Event-driven throughout. PulseAudio pushes every change, so nothing here
// wakes on a timer, and a read that moved nothing does not notify.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/pulse_client.dart';

/// Which way a device carries sound.
enum AudioDirection { output, input }

/// One sink or source, reduced to what the panel draws.
@immutable
class AudioDevice {
  const AudioDevice({
    required this.index,
    required this.name,
    required this.description,
    required this.volume,
    required this.muted,
  });

  /// PulseAudio's index, which is all a removal event carries.
  final int index;

  /// The device's PulseAudio name — what every write is addressed to.
  final String name;

  /// What a person reads: `Built-in Audio Analog Stereo`.
  final String description;

  /// 0..1, the loudest channel — the level a balance sits under.
  final double volume;
  final bool muted;

  /// The name when the server gave the device no description.
  String get label => description.isEmpty ? name : description;

  @override
  bool operator ==(Object other) =>
      other is AudioDevice &&
      other.index == index &&
      other.name == name &&
      other.description == description &&
      other.volume == volume &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(index, name, description, volume, muted);
}

/// Whether [name] is a sink's monitor — the loopback every sink exposes as a
/// source. Recording from one is not what "microphone" means, so the input
/// list leaves them out, as the Audio settings' Input tab does.
bool isMonitorSource(String name) => name.endsWith('.monitor');

/// The PulseAudio calls the store makes, behind a seam so a test can drive it
/// without a server.
abstract class AudioDevicesBackend {
  Future<void> initialize();

  /// The default sink's and source's names.
  Future<({String output, String input})> defaults();

  Future<List<AudioDevice>> devices(AudioDirection direction);

  /// A device appeared or changed.
  Stream<(AudioDirection, AudioDevice)> get changed;

  /// A device went away, by index.
  Stream<(AudioDirection, int)> get removed;

  /// The default sink or source moved.
  Stream<({String output, String input})> get defaultsChanged;

  /// The server went away and came back; everything read before is stale.
  Stream<void> get reconnected;

  Future<void> setVolume(AudioDirection direction, String name, double volume);
  Future<void> setMute(AudioDirection direction, String name, bool muted);
  Future<void> setDefault(AudioDirection direction, String name);
}

/// [AudioDevicesBackend] over the process's one [PulseClient].
class PulseAudioDevicesBackend implements AudioDevicesBackend {
  PulseClient get _client => PulseClient();

  static AudioDevice _sink(PaSink s) => AudioDevice(
    index: s.index,
    name: s.name,
    description: s.description,
    volume: s.volume,
    muted: s.mute,
  );

  static AudioDevice _source(PaSource s) => AudioDevice(
    index: s.index,
    name: s.name,
    description: s.description,
    volume: s.volume,
    muted: s.mute,
  );

  @override
  Future<void> initialize() => _client.initialize();

  @override
  Future<({String output, String input})> defaults() async {
    final info = await _client.getServerInfo();
    return (output: info.defaultSinkName, input: info.defaultSourceName);
  }

  @override
  Future<List<AudioDevice>> devices(AudioDirection direction) async =>
      switch (direction) {
        AudioDirection.output => [
          for (final s in await _client.getSinkList()) _sink(s),
        ],
        AudioDirection.input => [
          for (final s in await _client.getSourceList()) _source(s),
        ],
      };

  @override
  Stream<(AudioDirection, AudioDevice)> get changed => _merge([
    _client.onSinkChanged.map((s) => (AudioDirection.output, _sink(s))),
    _client.onSourceChanged.map((s) => (AudioDirection.input, _source(s))),
  ]);

  @override
  Stream<(AudioDirection, int)> get removed => _merge([
    _client.onSinkRemoved.map((i) => (AudioDirection.output, i)),
    _client.onSourceRemoved.map((i) => (AudioDirection.input, i)),
  ]);

  @override
  Stream<({String output, String input})> get defaultsChanged =>
      _client.onServerChanged.map(
        (info) => (output: info.defaultSinkName, input: info.defaultSourceName),
      );

  @override
  Stream<void> get reconnected => _client.onReconnected;

  @override
  Future<void> setVolume(AudioDirection direction, String name, double v) =>
      switch (direction) {
        AudioDirection.output => _client.setSinkVolume(name, v),
        AudioDirection.input => _client.setSourceVolume(name, v),
      };

  @override
  Future<void> setMute(AudioDirection direction, String name, bool muted) =>
      switch (direction) {
        AudioDirection.output => _client.setSinkMute(name, muted),
        AudioDirection.input => _client.setSourceMute(name, muted),
      };

  @override
  Future<void> setDefault(AudioDirection direction, String name) =>
      switch (direction) {
        AudioDirection.output => _client.setDefaultSink(name),
        AudioDirection.input => _client.setDefaultSource(name),
      };
}

/// The merge of several broadcast streams, without a package for it.
Stream<T> _merge<T>(List<Stream<T>> streams) {
  late final StreamController<T> controller;
  final subs = <StreamSubscription<T>>[];
  controller = StreamController<T>.broadcast(
    onListen: () {
      for (final s in streams) {
        subs.add(s.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}

/// How far along the store's view of the sound server is.
enum AudioDevicesStatus { idle, loading, ready, unavailable }

class AudioDevicesStore extends ChangeNotifier {
  AudioDevicesStore._(this._backend);

  static final AudioDevicesStore instance = AudioDevicesStore._(
    PulseAudioDevicesBackend(),
  );

  @visibleForTesting
  factory AudioDevicesStore.forTesting(AudioDevicesBackend backend) =>
      AudioDevicesStore._(backend);

  final AudioDevicesBackend _backend;

  // --- published state -----------------------------------------------------

  AudioDevicesStatus _status = AudioDevicesStatus.idle;
  AudioDevicesStatus get status => _status;

  String _error = '';

  /// Why the server could not be read, or empty. The last good lists stay.
  String get error => _error;

  final Map<AudioDirection, List<AudioDevice>> _devices = {
    AudioDirection.output: const [],
    AudioDirection.input: const [],
  };

  final Map<AudioDirection, String> _defaults = {
    AudioDirection.output: '',
    AudioDirection.input: '',
  };

  /// Every device in [direction], in the server's order; monitors left out
  /// of the inputs.
  List<AudioDevice> devices(AudioDirection direction) => _devices[direction]!;

  /// The default device's name in [direction], or empty.
  String defaultName(AudioDirection direction) => _defaults[direction]!;

  /// The default device in [direction], or null while there is none — no
  /// microphone, or a server that has not answered.
  AudioDevice? current(AudioDirection direction) {
    final name = _defaults[direction]!;
    for (final d in _devices[direction]!) {
      if (d.name == name) return d;
    }
    return null;
  }

  // --- leases --------------------------------------------------------------

  int _leases = 0;
  final List<StreamSubscription<Object?>> _subs = [];

  /// Bumped by every start and every last release, so a start still waiting
  /// on the server when its lease went (and a new one came) does not
  /// subscribe a second time beside the new start.
  int _generation = 0;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Takes a lease. Notifies nothing synchronously: this runs inside the
  /// acquirer's `initState`.
  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_status == AudioDevicesStatus.idle) {
      _status = AudioDevicesStatus.loading;
    }
    unawaited(_start());
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0) return;
    _generation++;
    // The values stay: the next lease's first frame shows them, not a loader.
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  /// Tries the server again after a failure.
  Future<void> retry() async {
    if (_leases == 0) return;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _status = AudioDevicesStatus.loading;
    notifyListeners();
    await _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    try {
      await _backend.initialize();
    } catch (e) {
      if (generation == _generation) {
        _fail('The sound server is not running ($e).');
      }
      return;
    }
    if (_leases == 0 || generation != _generation) return;
    // Subscribed before the first read, never after — `SoundControl`'s rule:
    // a read that fails would otherwise cost the subscriptions for the rest of
    // the lease. Events landing before the read are applied to empty lists and
    // then replaced by it.
    _subs
      ..add(_backend.changed.listen((e) => _upsert(e.$1, e.$2)))
      ..add(_backend.removed.listen((e) => _remove(e.$1, e.$2)))
      ..add(_backend.defaultsChanged.listen(_setDefaults))
      ..add(_backend.reconnected.listen((_) => unawaited(_read())));
    await _read();
  }

  Future<void> _read() async {
    try {
      final results = await Future.wait([
        _backend.defaults(),
        _backend.devices(AudioDirection.output),
        _backend.devices(AudioDirection.input),
      ]);
      if (_leases == 0) return;
      final defaults = results[0] as ({String output, String input});
      _devices[AudioDirection.output] = List.unmodifiable(
        results[1] as List<AudioDevice>,
      );
      _devices[AudioDirection.input] = List.unmodifiable(
        (results[2] as List<AudioDevice>).where(
          (d) => !isMonitorSource(d.name),
        ),
      );
      _defaults[AudioDirection.output] = defaults.output;
      _defaults[AudioDirection.input] = defaults.input;
      _status = AudioDevicesStatus.ready;
      _error = '';
      notifyListeners();
    } catch (e) {
      _fail('Could not read the sound devices ($e).');
    }
  }

  void _fail(String message) {
    _status = AudioDevicesStatus.unavailable;
    _error = message;
    notifyListeners();
  }

  void _upsert(AudioDirection direction, AudioDevice device) {
    if (direction == AudioDirection.input && isMonitorSource(device.name)) {
      return;
    }
    final list = _devices[direction]!;
    final at = list.indexWhere((d) => d.index == device.index);
    if (at >= 0 && list[at] == device) return;
    final next = [...list];
    if (at >= 0) {
      next[at] = device;
    } else {
      next.add(device);
    }
    _devices[direction] = List.unmodifiable(next);
    notifyListeners();
  }

  void _remove(AudioDirection direction, int index) {
    final list = _devices[direction]!;
    if (!list.any((d) => d.index == index)) return;
    _devices[direction] = List.unmodifiable(
      list.where((d) => d.index != index),
    );
    notifyListeners();
  }

  void _setDefaults(({String output, String input}) defaults) {
    if (defaults.output == _defaults[AudioDirection.output] &&
        defaults.input == _defaults[AudioDirection.input]) {
      return;
    }
    _defaults[AudioDirection.output] = defaults.output;
    _defaults[AudioDirection.input] = defaults.input;
    notifyListeners();
  }

  // --- writes --------------------------------------------------------------

  /// Sets the default device's level in [direction].
  ///
  /// Shown at once rather than on the server's echo, so a scroll steps from
  /// where the last notch put it; the echo lands within a rounding of it.
  Future<void> setVolume(AudioDirection direction, double volume) async {
    final device = current(direction);
    if (device == null) return;
    _upsert(
      direction,
      AudioDevice(
        index: device.index,
        name: device.name,
        description: device.description,
        volume: volume.clamp(0.0, 1.0),
        muted: device.muted,
      ),
    );
    try {
      await _backend.setVolume(direction, device.name, volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('Could not set the ${direction.name} volume: $e');
    }
  }

  Future<void> setMuted(AudioDirection direction, bool muted) async {
    final device = current(direction);
    if (device == null || device.muted == muted) return;
    _upsert(
      direction,
      AudioDevice(
        index: device.index,
        name: device.name,
        description: device.description,
        volume: device.volume,
        muted: muted,
      ),
    );
    try {
      await _backend.setMute(direction, device.name, muted);
    } catch (e) {
      debugPrint('Could not ${muted ? 'mute' : 'unmute'} the device: $e');
    }
  }

  /// Makes [name] the default in [direction]. The selection follows the
  /// server's answer — a `defaultsChanged` event — rather than the request,
  /// so a refused switch is self-evidently a no-op.
  Future<void> setDefault(AudioDirection direction, String name) async {
    if (_defaults[direction] == name) return;
    try {
      await _backend.setDefault(direction, name);
    } catch (e) {
      debugPrint('Could not switch the default ${direction.name}: $e');
    }
  }
}
