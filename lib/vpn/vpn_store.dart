// The VPN half of Settings › Network.
//
// `PowerProfileStore`'s shape: a singleton held by leases (the pane's), state
// *derived* from what NetworkManager reports rather than set optimistically —
// a switch flipped in `nmcli` moves the pane's, and one NetworkManager refuses
// visibly springs back — and a failure kept on screen with a retry.
//
// Two kinds of failure, kept apart. NetworkManager missing, or the list not
// reading, is the pane's: a banner, the last good list under it. A profile
// failing to come up is that profile's: its row says why, from the reason
// NetworkManager gives as the activation ends, and offers a password where a
// password is what was missing. A tunnel that drops on its own is the same
// failure, on a row whose switch the user did not touch.
//
// Flutter-free below `foundation`, so a test drives it over a fake backend.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/vpn/libnm_import.dart';
import 'package:moonswing/vpn/nm_vpn_client.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';
import 'package:moonswing/vpn/vpn_spec.dart';
import 'package:moonswing/vpn/wireguard_conf.dart';

enum VpnStoreStatus {
  /// No lease has been taken; nothing has been read.
  idle,

  /// The first read is in flight.
  loading,

  /// NetworkManager answered.
  ready,

  /// NetworkManager did not. The last good list, if any, stays.
  unavailable,
}

/// What a row's switch is waiting on.
enum VpnPending { connecting, disconnecting, removing }

/// Why a profile is not up when the user wanted it to be.
@immutable
class VpnProfileError {
  const VpnProfileError(this.message, {this.wantsPassword = false});

  final String message;

  /// Whether a password would plausibly fix it — the pane offers one.
  final bool wantsPassword;

  @override
  bool operator ==(Object other) =>
      other is VpnProfileError &&
      other.message == message &&
      other.wantsPassword == wantsPassword;

  @override
  int get hashCode => Object.hash(message, wantsPassword);
}

/// A file read and turned into a profile, not yet saved: the pane shows it so
/// the user can name it and, where the plugin needs one, give the password the
/// file could not carry.
@immutable
class VpnImportDraft {
  const VpnImportDraft({
    required this.path,
    required this.settings,
    required this.profile,
    this.warnings = const [],
  });

  final String path;
  final NmSettings settings;

  /// [settings] read as the list would read it — its kind, name and server.
  final VpnProfile profile;

  /// What of the file did not make it into the profile.
  final List<String> warnings;

  /// Whether the profile signs in with a password: every PPTP profile, and an
  /// OpenVPN one whose `connection-type` names one.
  bool get asksPassword {
    switch (profile.kind) {
      case VpnKind.pptp:
        return true;
      case VpnKind.openvpn:
        final type =
            nmStringMap(settings['vpn']?['data'])['connection-type'] ?? '';
        return type.contains('password');
      default:
        return false;
    }
  }

  /// The user name the file named, if any.
  String get username {
    final data = nmStringMap(settings['vpn']?['data']);
    return data['username'] ?? data['user'] ?? '';
  }
}

/// A random (version 4) UUID, as every NetworkManager profile has.
String randomUuid({Random? random}) {
  final rng = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

class VpnStore extends ChangeNotifier {
  VpnStore._({
    VpnBackend? backend,
    VpnPluginImporter? importer,
    List<VpnPluginInfo> Function()? readPlugins,
    String Function()? newUuid,
    Duration debounce = const Duration(milliseconds: 60),
  }) : _backend = backend ?? DBusVpnBackend(),
       _importer = importer ?? LibnmImporter(),
       _readPlugins = readPlugins ?? readVpnPlugins,
       _newUuid = newUuid ?? randomUuid,
       _debounce = debounce;

  static final VpnStore instance = VpnStore._();

  /// A detached store over fakes. A test must never take the real one: it
  /// would add and remove the profiles of the machine running it.
  @visibleForTesting
  factory VpnStore.forTesting({
    required VpnBackend backend,
    VpnPluginImporter? importer,
    List<VpnPluginInfo> Function()? readPlugins,
    String Function()? newUuid,
    Duration debounce = Duration.zero,
  }) => VpnStore._(
    backend: backend,
    importer: importer,
    readPlugins: readPlugins ?? () => const [],
    newUuid: newUuid,
    debounce: debounce,
  );

  final VpnBackend _backend;
  final VpnPluginImporter _importer;
  final List<VpnPluginInfo> Function() _readPlugins;
  final String Function() _newUuid;
  final Duration _debounce;

  VpnStoreStatus _status = VpnStoreStatus.idle;
  VpnStoreStatus get status => _status;

  String _error = '';

  /// Why the list could not be read, or empty.
  String get error => _error;

  List<VpnProfile> _profiles = const [];

  /// Every VPN NetworkManager has, by name.
  List<VpnProfile> get profiles => _profiles;

  Map<String, VpnActivation> _activations = const {};
  final Map<String, VpnPending> _pending = {};
  final Map<String, VpnProfileError> _errors = {};

  List<VpnPluginInfo> _plugins = const [];

  /// The installed VPN plugins, read when a lease is taken and on retry.
  List<VpnPluginInfo> get plugins => _plugins;

  /// The plugin a [kind] needs, or null when it is not installed.
  VpnPluginInfo? pluginFor(VpnKind kind) {
    for (final p in _plugins) {
      if (p.kind == kind) return p;
    }
    return null;
  }

  /// Where [profile] is: what NetworkManager says, unless the switch is
  /// waiting on a call it has not answered yet.
  VpnState stateOf(VpnProfile profile) {
    switch (_pending[profile.path]) {
      case VpnPending.connecting:
        return VpnState.connecting;
      case VpnPending.disconnecting:
        return VpnState.disconnecting;
      case _:
        return _activations[profile.path]?.state ?? VpnState.disconnected;
    }
  }

  VpnPending? pendingOf(VpnProfile profile) => _pending[profile.path];

  VpnProfileError? errorOf(VpnProfile profile) => _errors[profile.path];

  /// Interface names WireGuard profiles already use, which a new one must not.
  Iterable<String> get takenInterfaces => [
    for (final p in _profiles)
      if (p.interfaceName.isNotEmpty) p.interfaceName,
  ];

  // --- leases ----------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<VpnBackendEvent>? _events;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Takes a lease. Notifies nothing synchronously — this runs inside the
  /// acquiring widget's `initState`.
  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_status == VpnStoreStatus.idle) _status = VpnStoreStatus.loading;
    _events = _backend.events().listen(_onEvent, onError: (Object _) {});
    unawaited(_refreshAll());
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0) return;
    // The list stays: it is the last good reading, and the next lease's first
    // frame shows it rather than a loader.
    unawaited(_events?.cancel());
    _events = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Everything here recovers without a restart — NetworkManager started, a
  /// plugin installed — and the shell cannot see the second happen.
  Future<void> retry() => _refreshAll();

  Future<void> _refreshAll() async {
    try {
      _plugins = _readPlugins();
    } catch (_) {
      _plugins = const [];
    }
    await Future.wait([_refreshProfiles(), _refreshActivations()]);
  }

  // --- reading ---------------------------------------------------------------

  Timer? _debounceTimer;
  bool _profilesDirty = false;
  bool _activationsDirty = false;

  void _onEvent(VpnBackendEvent event) {
    switch (event) {
      case VpnProfilesChanged():
        _profilesDirty = true;
      case VpnActivationsChanged():
        _activationsDirty = true;
      case VpnActivationStateChanged(
        :final activePath,
        :final state,
        :final reason,
      ):
        _onActivationState(activePath, state, reason);
        _activationsDirty = true;
      case VpnServiceChanged():
        _profilesDirty = true;
        _activationsDirty = true;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      _debounceTimer = null;
      final profiles = _profilesDirty;
      final activations = _activationsDirty;
      _profilesDirty = false;
      _activationsDirty = false;
      if (profiles) unawaited(_refreshProfiles());
      if (activations) unawaited(_refreshActivations());
    });
  }

  /// Which connection each active connection this store has seen belongs to.
  /// An active connection is gone by the time a read could ask it, so the
  /// answer has to be known before it ends.
  final Map<String, String> _owners = {};

  /// End reasons for active connections not yet known to belong to anything —
  /// a failure fast enough to beat `ActivateConnection`'s own reply.
  final Map<String, int> _orphanReasons = {};

  void _onActivationState(String activePath, int state, int reason) {
    if (VpnState.fromActiveState(state) != VpnState.disconnected) return;
    // 0 is "unknown", which NetworkManager also reports for a deactivation
    // nobody explained; 4 is "deactivated". Only the latter ends anything.
    if (state != 4) return;
    final owner = _owners[activePath];
    if (owner == null) {
      _orphanReasons[activePath] = reason;
      return;
    }
    _recordEnd(owner, reason);
  }

  void _recordEnd(String connectionPath, int reason) {
    final message = vpnFailureReason(reason);
    if (message == null) {
      _errors.remove(connectionPath);
    } else {
      _errors[connectionPath] = VpnProfileError(
        message,
        wantsPassword: vpnReasonWantsPassword(reason),
      );
    }
    _notifyIfChanged();
  }

  bool _readingProfiles = false;

  Future<void> _refreshProfiles() async {
    if (_readingProfiles) {
      _profilesDirty = true;
      return;
    }
    _readingProfiles = true;
    try {
      final connections = await _backend.connections();
      final profiles = [
        for (final e in connections.entries)
          ?VpnProfile.fromSettings(e.key, e.value),
      ]..sort(_byName);
      _profiles = List.unmodifiable(profiles);
      final paths = {for (final p in profiles) p.path};
      _errors.removeWhere((path, _) => !paths.contains(path));
      _owners.removeWhere((_, path) => !paths.contains(path));
      _status = VpnStoreStatus.ready;
      _error = '';
    } on VpnBackendException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(VpnBackendException('$e'));
    } finally {
      _readingProfiles = false;
    }
    _notifyIfChanged();
    if (_profilesDirty && _leases > 0) {
      _profilesDirty = false;
      unawaited(_refreshProfiles());
    }
  }

  bool _readingActivations = false;

  Future<void> _refreshActivations() async {
    if (_readingActivations) {
      _activationsDirty = true;
      return;
    }
    _readingActivations = true;
    try {
      final activations = await _backend.activations();
      _activations = {for (final a in activations) a.connectionPath: a};
      for (final a in activations) {
        _owners[a.activePath] = a.connectionPath;
        if (a.state == VpnState.connected) _errors.remove(a.connectionPath);
      }
    } on VpnBackendException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(VpnBackendException('$e'));
    } finally {
      _readingActivations = false;
    }
    _notifyIfChanged();
    if (_activationsDirty && _leases > 0) {
      _activationsDirty = false;
      unawaited(_refreshActivations());
    }
  }

  void _fail(VpnBackendException e) {
    _error = e.message;
    if (e.unavailable || _status != VpnStoreStatus.ready) {
      _status = VpnStoreStatus.unavailable;
    }
    if (e.unavailable) _activations = const {};
  }

  static int _byName(VpnProfile a, VpnProfile b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.path.compareTo(b.path);
  }

  // --- switching -------------------------------------------------------------

  /// Brings [profile] up or takes it down. A refusal lands on the row.
  Future<void> setEnabled(VpnProfile profile, bool enabled) async {
    if (_pending.containsKey(profile.path)) return;
    final path = profile.path;
    if (enabled) {
      _pending[path] = VpnPending.connecting;
      _errors.remove(path);
      _notifyIfChanged();
      try {
        final active = await _backend.activate(path);
        _owners[active] = path;
        final early = _orphanReasons.remove(active);
        if (early != null) _recordEnd(path, early);
      } on VpnBackendException catch (e) {
        _errors[path] = VpnProfileError(e.message);
      }
    } else {
      final active = _activations[path];
      if (active == null) return;
      _pending[path] = VpnPending.disconnecting;
      _notifyIfChanged();
      try {
        await _backend.deactivate(active.activePath);
      } on VpnBackendException catch (e) {
        _errors[path] = VpnProfileError(e.message);
      }
    }
    _pending.remove(path);
    _notifyIfChanged();
    await _refreshActivations();
  }

  /// Deletes [profile] from NetworkManager, taking it down if it is up.
  /// Answers the refusal, or null.
  Future<String?> remove(VpnProfile profile) async {
    if (_pending.containsKey(profile.path)) return null;
    _pending[profile.path] = VpnPending.removing;
    _notifyIfChanged();
    String? failure;
    try {
      await _backend.delete(profile.path);
    } on VpnBackendException catch (e) {
      failure = e.message;
      _errors[profile.path] = VpnProfileError(e.message);
    }
    _pending.remove(profile.path);
    _notifyIfChanged();
    await _refreshProfiles();
    return failure;
  }

  // --- adding ----------------------------------------------------------------

  /// Saves a profile built by one of the forms. Throws a
  /// [VpnBackendException] for NetworkManager's refusal.
  Future<void> add(NmSettings Function(String uuid) build) async {
    await _backend.add(build(_newUuid()));
    await _refreshProfiles();
  }

  /// Reads [path] into a profile for the user to look over. Throws a
  /// [VpnImportException] for a file nothing installed can read.
  Future<VpnImportDraft> prepareImport(String path) async {
    String? text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (e) {
      throw VpnImportException(
        'Could not read ${_baseName(path)}: ${e.osError?.message ?? e.message}.',
      );
    } on FormatException {
      // Not UTF-8: not a WireGuard file, though a plugin may still read it.
    }
    if (text != null && looksLikeWireGuardConf(text)) {
      final WireGuardImport parsed;
      try {
        parsed = parseWireGuardConf(
          text,
          path: path,
          takenInterfaces: takenInterfaces,
        );
      } on FormatException catch (e) {
        throw VpnImportException(e.message);
      }
      final problem = parsed.spec.validate();
      if (problem != null) throw VpnImportException(problem);
      final settings = parsed.spec.toSettings(uuid: _newUuid());
      return VpnImportDraft(
        path: path,
        settings: settings,
        profile: VpnProfile.fromSettings('', settings)!,
        warnings: parsed.warnings,
      );
    }
    try {
      _plugins = _readPlugins();
    } catch (_) {}
    final imported = _importer.importFile(path, _plugins);
    final settings = _normaliseImport(imported, path);
    final profile = VpnProfile.fromSettings('', settings);
    if (profile == null) {
      throw const VpnImportException(
        'The file describes a connection that is '
        'not a VPN.',
      );
    }
    return VpnImportDraft(path: path, settings: settings, profile: profile);
  }

  /// What `nmcli` does to a plugin's import before saving it: a plugin fills
  /// in only the settings its format has, so the profile's type and uuid —
  /// which NetworkManager refuses a profile without — are the caller's.
  NmSettings _normaliseImport(NmSettings imported, String path) {
    final settings = nmCopySettings(imported);
    final connection = settings['connection'] ??= {};
    if (nmString(connection['type']).isEmpty) {
      final type = settings.containsKey('vpn')
          ? 'vpn'
          : settings.containsKey('wireguard')
          ? 'wireguard'
          : '';
      if (type.isNotEmpty) connection['type'] = DBusString(type);
    }
    if (nmString(connection['uuid']).isEmpty) {
      connection['uuid'] = DBusString(_newUuid());
    }
    if (nmString(connection['id']).trim().isEmpty) {
      var name = _baseName(path);
      final dot = name.lastIndexOf('.');
      if (dot > 0) name = name.substring(0, dot);
      connection['id'] = DBusString(name);
    }
    connection['autoconnect'] = const DBusBoolean(false);
    return settings;
  }

  /// Saves [draft] under [name], with the sign-in the user gave it.
  Future<void> saveImport(
    VpnImportDraft draft, {
    required String name,
    String username = '',
    String password = '',
  }) async {
    var settings = nmCopySettings(draft.settings);
    final connection = settings['connection'] ??= {};
    if (name.trim().isNotEmpty) {
      connection['id'] = DBusString(name.trim());
    }
    if (draft.asksPassword && (password.isNotEmpty || username.isNotEmpty)) {
      settings =
          withVpnPassword(
            settings,
            kind: draft.profile.kind,
            password: password,
            username: username,
            existingSecrets: nmStringMap(settings['vpn']?['secrets']),
          ) ??
          settings;
      if (password.isEmpty) {
        // A user name alone: no secret to store, so none to send.
        settings['vpn']?.remove('secrets');
      }
    }
    await _backend.add(settings);
    await _refreshProfiles();
  }

  /// Stores [password] (and [username], when given) in [profile], for one
  /// whose sign-in failed. Throws a [VpnBackendException] for NetworkManager's
  /// refusal.
  Future<void> setPassword(
    VpnProfile profile, {
    required String password,
    String? username,
  }) async {
    final settings = await _backend.settingsOf(profile.path);
    final existing = await _backend.vpnSecretsOf(profile.path);
    final updated = withVpnPassword(
      settings,
      kind: profile.kind,
      password: password,
      username: username,
      existingSecrets: existing,
    );
    if (updated == null) {
      throw VpnBackendException(
        'A ${profile.kindLabel} profile\'s password cannot be set here.',
      );
    }
    await _backend.update(profile.path, updated);
    _errors.remove(profile.path);
    _notifyIfChanged();
  }

  /// The user name [profile] signs in with, for the password form to start
  /// from. Empty when it has none or cannot be read.
  Future<String> usernameOf(VpnProfile profile) async {
    try {
      final settings = await _backend.settingsOf(profile.path);
      final data = nmStringMap(settings['vpn']?['data']);
      return data['username'] ?? data['user'] ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  // --- notifying -------------------------------------------------------------

  List<Object?> _signature = const [];

  /// Notifies only when something a row renders moved — a signal burst from
  /// an unrelated `Updated` reads the same list and must stay silent.
  void _notifyIfChanged() {
    final signature = <Object?>[
      _status,
      _error,
      for (final p in _plugins) p.service,
      null,
      for (final p in _profiles) ...[
        p,
        stateOf(p),
        _pending[p.path],
        _errors[p.path],
      ],
    ];
    if (listEquals(signature, _signature)) return;
    _signature = signature;
    notifyListeners();
  }
}
