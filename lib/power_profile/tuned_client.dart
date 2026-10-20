// TuneD, the fine-grained profile daemon some distributions ship instead of
// power-profiles-daemon.
//
// Where it runs, its `tuned-ppd` shim answers the power-profiles-daemon
// interface with three of its profiles, so the pane's power mode works either
// way. This client is the rest: TuneD's own catalogue — `powersave`,
// `latency-performance`, `throughput-performance`, `virtual-guest`, a vendor's
// or the user's own — of which the three modes are only a mapping.
//
// TuneD answers every call with a value rather than an error when it refuses
// (`switch_profile` is `(bs)`, a success flag and a message), so a refusal
// arrives as a [TunedFailure] built from that message.
//
// Flutter-free.

import 'package:dbus/dbus.dart';

import 'package:moonswing/dbus_clients.dart';

const String kTunedBusName = 'com.redhat.tuned';
const String kTunedPath = '/Tuned';
const String kTunedInterface = 'com.redhat.tuned.control';

/// One profile TuneD can apply.
class TunedProfile {
  const TunedProfile(this.name, [this.summary = '']);

  final String name;
  final String summary;

  @override
  bool operator ==(Object other) =>
      other is TunedProfile && other.name == name && other.summary == summary;

  @override
  int get hashCode => Object.hash(name, summary);
}

/// What TuneD reports.
class TunedState {
  const TunedState({
    required this.active,
    this.profiles = const [],
    this.automatic = false,
    this.recommended = '',
  });

  /// The applied profile — space-separated when several are merged, which is
  /// how `tuned-adm profile a b` is written.
  final String active;

  /// Sorted by name, as TuneD lists them.
  final List<TunedProfile> profiles;

  /// Whether TuneD picked [active] itself (`auto_profile`), as opposed to the
  /// user or an administrator naming it.
  final bool automatic;

  /// What TuneD would pick for this machine.
  final String recommended;

  @override
  bool operator ==(Object other) =>
      other is TunedState &&
      other.active == active &&
      other.automatic == automatic &&
      other.recommended == recommended &&
      other.profiles.length == profiles.length &&
      Iterable.generate(
        profiles.length,
      ).every((i) => other.profiles[i] == profiles[i]);

  @override
  int get hashCode =>
      Object.hash(active, Object.hashAll(profiles), automatic, recommended);
}

/// Reads a `profiles2` reply (`a(ss)`) into profiles, dropping any malformed
/// row rather than the list.
List<TunedProfile> parseTunedProfiles2(DBusValue value) {
  if (value is! DBusArray) return const [];
  final out = <TunedProfile>[];
  for (final child in value.children) {
    if (child is! DBusStruct || child.children.length < 2) continue;
    final name = child.children[0];
    final summary = child.children[1];
    if (name is! DBusString || name.value.isEmpty) continue;
    out.add(
      TunedProfile(name.value, summary is DBusString ? summary.value : ''),
    );
  }
  return out;
}

/// Reads the older `profiles` reply (`as`).
List<TunedProfile> parseTunedProfiles(DBusValue value) {
  if (value is! DBusArray) return const [];
  return [
    for (final child in value.children)
      if (child is DBusString && child.value.isNotEmpty)
        TunedProfile(child.value),
  ];
}

enum TunedFailureKind { unavailable, refused }

class TunedFailure implements Exception {
  const TunedFailure(this.kind, this.message);

  final TunedFailureKind kind;
  final String message;

  @override
  String toString() => 'TunedFailure($kind): $message';
}

/// The seam a test replaces. See [DBusTunedClient].
abstract class TunedClient {
  /// Throws [TunedFailure]; [TunedFailureKind.unavailable] on a machine with
  /// no TuneD, which the pane treats as "draw no TuneD section".
  Future<TunedState> read();

  /// Fires after TuneD applies a profile — whoever asked for it.
  Stream<void> get changes;

  /// Throws [TunedFailure].
  Future<void> switchProfile(String name);

  /// Hands the choice back to TuneD's own recommendation. Throws
  /// [TunedFailure].
  Future<void> useRecommended();
}

class DBusTunedClient implements TunedClient {
  DBusTunedClient({DBusClient? bus}) : _bus = bus;

  final DBusClient? _bus;

  DBusRemoteObject? _object;

  DBusRemoteObject get _remote => _object ??= DBusRemoteObject(
    _bus ?? systemBus,
    name: kTunedBusName,
    path: DBusObjectPath(kTunedPath),
  );

  Future<DBusValue> _call(
    String method, [
    List<DBusValue> args = const [],
  ]) async {
    try {
      final reply = await _remote.callMethod(
        kTunedInterface,
        method,
        args,
        allowInteractiveAuthorization: true,
      );
      if (reply.returnValues.isEmpty) return const DBusBoolean(true);
      return reply.returnValues.first;
    } on DBusMethodResponseException catch (e) {
      switch (e.errorName) {
        case 'org.freedesktop.DBus.Error.ServiceUnknown':
        case 'org.freedesktop.DBus.Error.NameHasNoOwner':
        case 'org.freedesktop.DBus.Error.UnknownObject':
        case 'org.freedesktop.DBus.Error.NoReply':
        case 'org.freedesktop.DBus.Error.Timeout':
        case 'org.freedesktop.DBus.Error.Disconnected':
          throw const TunedFailure(
            TunedFailureKind.unavailable,
            'TuneD is not running.',
          );
        default:
          throw TunedFailure(TunedFailureKind.refused, e.toString());
      }
    } catch (e) {
      throw TunedFailure(TunedFailureKind.unavailable, '$e');
    }
  }

  @override
  Future<TunedState> read() async {
    final active = await _call('active_profile');
    List<TunedProfile> profiles;
    try {
      profiles = parseTunedProfiles2(await _call('profiles2'));
    } on TunedFailure catch (e) {
      // `profiles2` arrived in TuneD 2.11; an older daemon answers
      // UnknownMethod, which lands here as a refusal.
      if (e.kind == TunedFailureKind.unavailable) rethrow;
      profiles = parseTunedProfiles(await _call('profiles'));
    }
    var automatic = false;
    try {
      final mode = await _call('profile_mode');
      if (mode is DBusStruct && mode.children.isNotEmpty) {
        final first = mode.children.first;
        automatic = first is DBusString && first.value == 'auto';
      }
    } on TunedFailure {
      // Optional: the mode only labels the row.
    }
    var recommended = '';
    try {
      final value = await _call('recommend_profile');
      if (value is DBusString) recommended = value.value;
    } on TunedFailure {
      // Optional too.
    }
    return TunedState(
      active: active is DBusString ? active.value : '',
      profiles: profiles,
      automatic: automatic,
      recommended: recommended,
    );
  }

  @override
  Stream<void> get changes => DBusRemoteObjectSignalStream(
    object: _remote,
    interface: kTunedInterface,
    name: 'profile_changed',
  ).map((_) {});

  /// `(bs)`: a refusal is a false flag and TuneD's own sentence.
  Future<void> _expectSuccess(DBusValue reply) async {
    if (reply is! DBusStruct || reply.children.isEmpty) return;
    final ok = reply.children.first;
    if (ok is DBusBoolean && ok.value) return;
    final message = reply.children.length > 1 ? reply.children[1] : null;
    throw TunedFailure(
      TunedFailureKind.refused,
      message is DBusString && message.value.isNotEmpty
          ? message.value
          : 'TuneD refused the profile.',
    );
  }

  @override
  Future<void> switchProfile(String name) async =>
      _expectSuccess(await _call('switch_profile', [DBusString(name)]));

  @override
  Future<void> useRecommended() async =>
      _expectSuccess(await _call('auto_profile'));
}
