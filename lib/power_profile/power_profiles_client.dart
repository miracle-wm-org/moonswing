// power-profiles-daemon, which is where the machine's power mode lives.
//
// The high-level half of Settings › Power: three modes (power saver, balanced,
// performance) that the daemon maps onto whatever the hardware offers — the
// ACPI platform profile, the CPU's energy/performance preference, AMD's panel
// power savings — so one choice here moves all of them together. tuned-ppd
// serves the same interface, so a TuneD machine answers it too.
//
// Two names for one daemon: 0.20 moved the API to
// `org.freedesktop.UPower.PowerProfiles` and kept `net.hadess.PowerProfiles`
// as an alias, and an older install has only the latter. The client asks for
// the new one first and remembers which answered.
//
// Flutter-free, so parsing and the error table are plain unit tests.

import 'package:dbus/dbus.dart';

import 'package:moonswing/dbus_clients.dart';

/// One spelling of the daemon's address: bus name, object path and interface
/// are the same string in each, dotted and slashed.
class PowerProfilesAddress {
  const PowerProfilesAddress(this.name, this.path);

  final String name;
  final String path;

  String get interface => name;
}

/// The two addresses, in the order they are tried.
const List<PowerProfilesAddress> kPowerProfilesAddresses = [
  PowerProfilesAddress(
    'org.freedesktop.UPower.PowerProfiles',
    '/org/freedesktop/UPower/PowerProfiles',
  ),
  PowerProfilesAddress('net.hadess.PowerProfiles', '/net/hadess/PowerProfiles'),
];

/// The three profile ids the daemon can offer, in its own order.
abstract final class PowerProfileId {
  static const String powerSaver = 'power-saver';
  static const String balanced = 'balanced';
  static const String performance = 'performance';
}

/// One profile the daemon offers, and what implements it.
class PowerProfileInfo {
  const PowerProfileInfo({
    required this.profile,
    this.driver = '',
    this.platformDriver = '',
    this.cpuDriver = '',
  });

  /// One of [PowerProfileId], or a value a newer daemon added.
  final String profile;

  /// The backend: `intel_pstate`, `amd_pstate`, `platform_profile`,
  /// `placeholder` (no hardware support at all), or `multiple` on 0.20+ where
  /// [platformDriver] and [cpuDriver] say which.
  final String driver;
  final String platformDriver;
  final String cpuDriver;

  /// Whether the daemon has nothing behind this profile — the `placeholder`
  /// driver, which records the choice and changes no hardware.
  bool get isPlaceholder =>
      driver == 'placeholder' &&
      (platformDriver.isEmpty || platformDriver == 'placeholder') &&
      cpuDriver.isEmpty;

  /// The drivers in one line for a read-only row: `intel_pstate ·
  /// platform_profile`, or the single driver.
  String get driverSummary {
    final parts = [
      if (cpuDriver.isNotEmpty) cpuDriver,
      if (platformDriver.isNotEmpty) platformDriver,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return driver;
  }

  @override
  bool operator ==(Object other) =>
      other is PowerProfileInfo &&
      other.profile == profile &&
      other.driver == driver &&
      other.platformDriver == platformDriver &&
      other.cpuDriver == cpuDriver;

  @override
  int get hashCode => Object.hash(profile, driver, platformDriver, cpuDriver);
}

/// An application asking for a profile — a game holding `performance`, a
/// battery monitor holding `power-saver`. The daemon cancels every hold when
/// the user picks a profile by hand.
class PowerProfileHold {
  const PowerProfileHold({
    required this.applicationId,
    required this.profile,
    this.reason = '',
  });

  final String applicationId;
  final String profile;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is PowerProfileHold &&
      other.applicationId == applicationId &&
      other.profile == profile &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(applicationId, profile, reason);
}

/// Everything the daemon reports, as the Power pane renders it.
class PowerProfilesState {
  const PowerProfilesState({
    required this.active,
    this.profiles = const [],
    this.degraded = '',
    this.holds = const [],
    this.actions = const [],
    this.batteryAware,
    this.version = '',
  });

  /// The id of the profile in force.
  final String active;

  /// In the daemon's order: power saver, balanced, performance. Two entries on
  /// a machine whose hardware has no performance mode.
  final List<PowerProfileInfo> profiles;

  /// Why performance is being held back — `lap-detected`,
  /// `high-operating-temperature`, or a reason a newer daemon added — or
  /// empty. A comma-separated list on daemons that report several.
  final String degraded;

  final List<PowerProfileHold> holds;

  /// The extra behaviours the running daemon implements — `trickle_charge`,
  /// `amdgpu_panel_power`, `amdgpu_dpm`.
  final List<String> actions;

  /// Whether the daemon tunes its profiles further while on battery (0.30+).
  /// Null on a daemon that has no such property, where the row is not drawn.
  final bool? batteryAware;

  final String version;

  PowerProfileInfo? profile(String id) {
    for (final info in profiles) {
      if (info.profile == id) return info;
    }
    return null;
  }

  PowerProfilesState copyWith({String? active, bool? batteryAware}) =>
      PowerProfilesState(
        active: active ?? this.active,
        profiles: profiles,
        degraded: degraded,
        holds: holds,
        actions: actions,
        batteryAware: batteryAware ?? this.batteryAware,
        version: version,
      );

  @override
  bool operator ==(Object other) =>
      other is PowerProfilesState &&
      other.active == active &&
      _listEquals(other.profiles, profiles) &&
      other.degraded == degraded &&
      _listEquals(other.holds, holds) &&
      _listEquals(other.actions, actions) &&
      other.batteryAware == batteryAware &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    active,
    Object.hashAll(profiles),
    degraded,
    Object.hashAll(holds),
    Object.hashAll(actions),
    batteryAware,
    version,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reads a `GetAll` reply into a [PowerProfilesState].
///
/// Per-field degradation: a property of the wrong type, or a profile dict
/// missing its `Profile` key, costs that field or that row, never the read —
/// a daemon from next year that adds a key or changes one's type still shows
/// the user their mode.
PowerProfilesState parsePowerProfilesProperties(Map<String, DBusValue> props) {
  String str(DBusValue? value) => value is DBusString ? value.value : '';

  List<Map<String, DBusValue>> dicts(DBusValue? value) {
    if (value is! DBusArray) return const [];
    final out = <Map<String, DBusValue>>[];
    for (final child in value.children) {
      if (child is! DBusDict) continue;
      final map = <String, DBusValue>{};
      child.children.forEach((key, entry) {
        if (key is! DBusString) return;
        map[key.value] = entry is DBusVariant ? entry.value : entry;
      });
      out.add(map);
    }
    return out;
  }

  final profiles = <PowerProfileInfo>[
    for (final dict in dicts(props['Profiles']))
      if (str(dict['Profile']).isNotEmpty)
        PowerProfileInfo(
          profile: str(dict['Profile']),
          driver: str(dict['Driver']),
          platformDriver: str(dict['PlatformDriver']),
          cpuDriver: str(dict['CpuDriver']),
        ),
  ];

  final holds = <PowerProfileHold>[
    for (final dict in dicts(props['ActiveProfileHolds']))
      if (str(dict['Profile']).isNotEmpty)
        PowerProfileHold(
          applicationId: str(dict['ApplicationId']),
          profile: str(dict['Profile']),
          reason: str(dict['Reason']),
        ),
  ];

  final actionsValue = props['Actions'];
  final actions = <String>[
    if (actionsValue is DBusArray)
      for (final child in actionsValue.children)
        if (child is DBusString && child.value.isNotEmpty) child.value,
  ];

  final batteryAwareValue = props['BatteryAware'];
  return PowerProfilesState(
    active: str(props['ActiveProfile']),
    profiles: profiles,
    degraded: str(props['PerformanceDegraded']),
    holds: holds,
    actions: actions,
    batteryAware: batteryAwareValue is DBusBoolean
        ? batteryAwareValue.value
        : null,
    version: str(props['Version']),
  );
}

/// The user-facing name of a profile id. An id this table does not know is
/// shown as the daemon spells it, humanised, rather than dropped.
String powerProfileLabel(String id) => switch (id) {
  PowerProfileId.powerSaver => 'Power Saver',
  PowerProfileId.balanced => 'Balanced',
  PowerProfileId.performance => 'Performance',
  _ => humanizeIdentifier(id),
};

/// One sentence on what a profile trades.
String powerProfileDescription(String id) => switch (id) {
  PowerProfileId.powerSaver =>
    'Longest battery life and the quietest fans, at the cost of speed.',
  PowerProfileId.balanced =>
    'The everyday default: full speed when it is needed, savings when idle.',
  PowerProfileId.performance =>
    'Highest sustained speed. More heat, more fan noise, shorter battery life.',
  _ => '',
};

/// Why performance is degraded, as a sentence. Unknown reasons get the
/// generic wording the daemon's documentation asks front-ends to fall back to.
String powerDegradedReason(String reason) {
  final reasons = reason
      .split(',')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  if (reasons.isEmpty) return '';
  final sentences = <String>{
    for (final r in reasons)
      switch (r) {
        'lap-detected' =>
          'The computer has detected it is sitting on a lap, so it is '
              'keeping itself cool.',
        'high-operating-temperature' =>
          'The computer is close to overheating, so it is holding back '
              'until it cools down.',
        _ => 'The hardware is holding performance back ($r).',
      },
  };
  return sentences.join(' ');
}

/// What a daemon action does, for its read-only row. Null for an action this
/// table does not describe — the row then shows only its humanised name.
String? powerActionDescription(String action) => switch (action) {
  'trickle_charge' =>
    'Charges the battery more gently in Power Saver, which is easier on it.',
  'amdgpu_panel_power' =>
    'Lets an AMD GPU dim and re-tune the panel to save power on battery.',
  'amdgpu_dpm' => 'Moves an AMD GPU\'s clock policy with the mode.',
  _ => null,
};

/// `trickle_charge` → `Trickle charge`; `amdgpu_dpm` → `Amdgpu dpm`. The
/// fallback for any identifier a daemon reports that the shell has no name
/// for.
String humanizeIdentifier(String id) {
  final words = id
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return id;
  final first = words.first;
  return [
    '${first[0].toUpperCase()}${first.substring(1)}',
    ...words.skip(1),
  ].join(' ');
}

/// Why a read or write did not land. [denied] covers "no authentication agent
/// answered" too: polkit returns the same error for both.
enum PowerProfilesFailureKind { unavailable, denied, failed }

class PowerProfilesFailure implements Exception {
  const PowerProfilesFailure(this.kind, this.message);

  final PowerProfilesFailureKind kind;

  /// A sentence for the user, not a D-Bus error name.
  final String message;

  @override
  String toString() => 'PowerProfilesFailure($kind): $message';
}

/// Classifies a D-Bus error name. Pure, so the table is pinned by a test.
PowerProfilesFailure mapPowerProfilesError(String errorName, String detail) {
  switch (errorName) {
    case 'org.freedesktop.DBus.Error.ServiceUnknown':
    case 'org.freedesktop.DBus.Error.NameHasNoOwner':
    case 'org.freedesktop.DBus.Error.UnknownObject':
    case 'org.freedesktop.DBus.Error.UnknownInterface':
    case 'org.freedesktop.DBus.Error.NoReply':
    case 'org.freedesktop.DBus.Error.Timeout':
    case 'org.freedesktop.DBus.Error.TimedOut':
    case 'org.freedesktop.DBus.Error.NoServer':
    case 'org.freedesktop.DBus.Error.Disconnected':
      return const PowerProfilesFailure(
        PowerProfilesFailureKind.unavailable,
        'No power profile service is running. Install and enable '
        'power-profiles-daemon (or TuneD\'s tuned-ppd) to switch modes.',
      );
    case 'org.freedesktop.DBus.Error.AccessDenied':
    case 'org.freedesktop.DBus.Error.AuthFailed':
    case 'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired':
      return const PowerProfilesFailure(
        PowerProfilesFailureKind.denied,
        'The system refused the change. Switching the power mode is allowed '
        'for the active session by default; a local polkit rule may have '
        'restricted it.',
      );
    default:
      return PowerProfilesFailure(
        PowerProfilesFailureKind.failed,
        detail.isEmpty ? 'The power mode could not be changed.' : detail,
      );
  }
}

/// The seam a test replaces. See [DBusPowerProfilesClient].
abstract class PowerProfilesClient {
  /// Throws [PowerProfilesFailure].
  Future<PowerProfilesState> read();

  /// Fires whenever the daemon reports a property moved — including a change
  /// made by `powerprofilesctl`, a hold, or the hardware degrading.
  Stream<PowerProfilesState> get changes;

  /// Throws [PowerProfilesFailure].
  Future<void> setActiveProfile(String profile);

  /// Throws [PowerProfilesFailure].
  Future<void> setBatteryAware(bool enabled);
}

class DBusPowerProfilesClient implements PowerProfilesClient {
  DBusPowerProfilesClient({DBusClient? bus}) : _bus = bus;

  /// Null resolves to the process-wide [systemBus] at first use, so
  /// constructing one — which the store does eagerly — opens nothing.
  final DBusClient? _bus;

  PowerProfilesAddress? _address;
  DBusRemoteObject? _object;

  DBusRemoteObject _remote(PowerProfilesAddress address) => DBusRemoteObject(
    _bus ?? systemBus,
    name: address.name,
    path: DBusObjectPath(address.path),
  );

  /// The address that answered, found by trying each in turn. Re-probed after
  /// any read that fails, so a daemon upgraded or restarted under a running
  /// shell is found again by Retry.
  Future<(PowerProfilesAddress, DBusRemoteObject, Map<String, DBusValue>)>
  _resolve() async {
    final known = _address;
    final candidates = known == null
        ? kPowerProfilesAddresses
        : [known, ...kPowerProfilesAddresses.where((a) => a != known)];
    Object? lastError;
    for (final address in candidates) {
      final object = _remote(address);
      try {
        final props = await object.getAllProperties(address.interface);
        _address = address;
        _object = object;
        return (address, object, props);
      } catch (e) {
        lastError = e;
      }
    }
    _address = null;
    _object = null;
    throw lastError ?? StateError('no power profile service');
  }

  @override
  Future<PowerProfilesState> read() async {
    try {
      final (_, _, props) = await _resolve();
      return parsePowerProfilesProperties(props);
    } on DBusMethodResponseException catch (e) {
      throw mapPowerProfilesError(e.errorName, e.toString());
    } catch (e) {
      throw mapPowerProfilesError('', e.toString());
    }
  }

  /// Re-reads rather than applying the signal's payload: `Profiles` and the
  /// holds arrive as whole arrays anyway, and one `GetAll` per change is free
  /// at the rate a power mode moves.
  @override
  Stream<PowerProfilesState> get changes async* {
    try {
      await _resolve();
    } catch (_) {
      return;
    }
    final object = _object!;
    final interface = _address!.interface;
    yield* object.propertiesChanged
        .where((signal) => signal.propertiesInterface == interface)
        .asyncMap((_) => read())
        // A failed re-read is one missed update; the next signal corrects it.
        .handleError((Object _) {});
  }

  Future<void> _set(String property, DBusValue value) async {
    try {
      var object = _object;
      var address = _address;
      if (object == null || address == null) {
        final resolved = await _resolve();
        address = resolved.$1;
        object = resolved.$2;
      }
      // `Properties.Set` spelled out rather than `setProperty`, which has no
      // way to allow interactive authorization — and a prompt, where a local
      // polkit rule asks for one, is the user's to answer.
      await object.callMethod(
        'org.freedesktop.DBus.Properties',
        'Set',
        [
          DBusString(address.interface),
          DBusString(property),
          DBusVariant(value),
        ],
        replySignature: DBusSignature(''),
        allowInteractiveAuthorization: true,
      );
    } on DBusMethodResponseException catch (e) {
      throw mapPowerProfilesError(e.errorName, e.toString());
    } on PowerProfilesFailure {
      rethrow;
    } catch (e) {
      throw mapPowerProfilesError('', e.toString());
    }
  }

  @override
  Future<void> setActiveProfile(String profile) =>
      _set('ActiveProfile', DBusString(profile));

  @override
  Future<void> setBatteryAware(bool enabled) =>
      _set('BatteryAware', DBusBoolean(enabled));
}
