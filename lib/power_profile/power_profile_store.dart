// The machine's power mode and the knobs beneath it, for Settings › Power.
//
// Three sources, each optional and each failing on its own:
//
// * power-profiles-daemon (or tuned-ppd) — the mode, read and written over
//   D-Bus, with its holds, degradation and actions;
// * TuneD's own catalogue, where TuneD is the daemon;
// * the sysfs knobs, read directly and written as administrator in one batch.
//
// `KeyboardStore`'s shape: a singleton with leases, state *derived* from what
// the system reports rather than set optimistically (a refused write is then
// self-evidently a no-op, and a `powerprofilesctl set` typed into a terminal
// moves the pane), and a failure kept on screen with a retry until something
// succeeds.
//
// Flutter-free below `foundation`, so a test drives it with fakes.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/power_tuning.dart';
import 'package:moonswing/power_profile/tuned_client.dart';

/// How far along the store's view of the profile daemon is.
enum PowerProfilesStatus {
  /// Nothing holds a lease; nothing has been read.
  idle,

  /// The first read is in flight.
  loading,

  /// The daemon answered.
  ready,

  /// No daemon answered. The fine-grained knobs still work without one.
  unavailable,
}

class PowerProfileStore extends ChangeNotifier {
  PowerProfileStore._({
    PowerProfilesClient? profiles,
    TunedClient? tuned,
    SysfsReader? sysfs,
    PrivilegedSysfsWriter? writer,
  }) : _profiles = profiles ?? DBusPowerProfilesClient(),
       _tuned = tuned ?? DBusTunedClient(),
       _sysfs = sysfs ?? const IoSysfsReader(),
       _writer = writer ?? PkexecSysfsWriter();

  static final PowerProfileStore instance = PowerProfileStore._();

  /// A detached store over fakes. A unit test must never take the real one:
  /// it would change the power mode of the machine running the test.
  @visibleForTesting
  factory PowerProfileStore.forTesting({
    required PowerProfilesClient profiles,
    required TunedClient tuned,
    required SysfsReader sysfs,
    required PrivilegedSysfsWriter writer,
  }) => PowerProfileStore._(
    profiles: profiles,
    tuned: tuned,
    sysfs: sysfs,
    writer: writer,
  );

  final PowerProfilesClient _profiles;
  final TunedClient _tuned;
  final SysfsReader _sysfs;
  final PrivilegedSysfsWriter _writer;

  // --- power-profiles-daemon ------------------------------------------------

  PowerProfilesStatus _status = PowerProfilesStatus.idle;
  PowerProfilesStatus get status => _status;

  PowerProfilesState? _state;

  /// What the daemon last reported, or null before the first read. Kept
  /// through a later failure: the last good value stays on screen.
  PowerProfilesState? get state => _state;

  String _error = '';

  /// Why the last read or write did not land, or empty. Kept until something
  /// succeeds.
  String get error => _error;

  PowerProfilesFailureKind? _errorKind;
  PowerProfilesFailureKind? get errorKind => _errorKind;

  String? _pendingProfile;

  /// The profile a write is in flight for, or null.
  String? get pendingProfile => _pendingProfile;

  bool _pendingBatteryAware = false;
  bool get pendingBatteryAware => _pendingBatteryAware;

  // --- TuneD ----------------------------------------------------------------

  TunedState? _tunedState;

  /// TuneD's catalogue, or null on a machine without TuneD — the pane's cue to
  /// draw no TuneD section at all.
  TunedState? get tuned => _tunedState;

  String _tunedError = '';
  String get tunedError => _tunedError;

  String? _pendingTuned;

  /// The TuneD profile a switch is in flight for; the empty string while
  /// handing the choice back to TuneD's recommendation.
  String? get pendingTuned => _pendingTuned;

  // --- sysfs ----------------------------------------------------------------

  PowerTuning? _tuning;

  /// What the kernel exposes, or null before the first read.
  PowerTuning? get tuning => _tuning;

  PowerTuningEdits _edits = PowerTuningEdits.none;

  /// What the user has changed and not applied. Already reconciled against
  /// [tuning], so an edit back to the machine's value is no edit.
  PowerTuningEdits get edits => _edits;

  bool _applying = false;

  /// Whether an apply is waiting on `pkexec` — which may be the user reading
  /// the password prompt, so there is no timeout behind it.
  bool get applying => _applying;

  SysfsWriteFailure? _tuningError;
  SysfsWriteFailure? get tuningError => _tuningError;

  // --- leases ---------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<PowerProfilesState>? _profilesSub;
  StreamSubscription<void>? _tunedSub;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Takes a lease. Notifies nothing synchronously — this runs inside the
  /// acquiring widget's `initState`.
  void acquire() {
    _leases++;
    if (_leases > 1) return;
    if (_status == PowerProfilesStatus.idle) {
      _status = PowerProfilesStatus.loading;
    }
    unawaited(_refreshAll(subscribe: true));
  }

  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0) return;
    // Values stay: they are the last good reading, and the next lease's first
    // frame shows them instead of a loader. Unapplied edits stay too — a tab
    // switch is not the user discarding them.
    unawaited(_profilesSub?.cancel());
    unawaited(_tunedSub?.cancel());
    _profilesSub = null;
    _tunedSub = null;
  }

  Future<void> _refreshAll({bool subscribe = false}) async {
    await Future.wait([_readProfiles(), _readTuned(), _readTuning()]);
    if (subscribe && _leases > 0) {
      // Each subscription forgets itself when its stream ends — which is what
      // a daemon that was not running at the first lease's read does — so a
      // Retry once it is running subscribes afresh.
      _profilesSub ??= _profiles.changes.listen(
        _onProfilesChanged,
        onDone: () => _profilesSub = null,
      );
      if (_tunedState != null) {
        _tunedSub ??= _tuned.changes.listen(
          (_) => _onTunedChanged(),
          onDone: () => _tunedSub = null,
        );
      }
    }
  }

  /// Every failure here is recoverable without a restart — a daemon started,
  /// a package installed — and the shell cannot see it happen, so retrying is
  /// the user's.
  Future<void> retry() => _refreshAll(subscribe: true);

  /// The sysfs knobs have no change notification; the pane re-reads them on
  /// demand and after anything that is known to move them.
  Future<void> refreshTuning() => _readTuning();

  void _onProfilesChanged(PowerProfilesState next) {
    _setProfiles(next);
    // The daemon writes the platform profile and the EPP itself on every mode
    // change, so the knobs beneath it have moved too.
    unawaited(_readTuning());
  }

  void _onTunedChanged() {
    unawaited(_readTuned());
    unawaited(_readTuning());
  }

  /// [keepError] is for the read-back after a write: the read succeeding
  /// says nothing about whether the write did, so its error stays.
  Future<void> _readProfiles({bool keepError = false}) async {
    try {
      final next = await _profiles.read();
      final hadError =
          (!keepError && _error.isNotEmpty) ||
          _status != PowerProfilesStatus.ready;
      if (!keepError) {
        _error = '';
        _errorKind = null;
      }
      _status = PowerProfilesStatus.ready;
      if (!_setProfiles(next) && hadError) notifyListeners();
    } on PowerProfilesFailure catch (e) {
      _fail(e, status: e.kind == PowerProfilesFailureKind.unavailable);
    }
  }

  /// Notifies only when what the pane renders moved. Returns whether it did.
  bool _setProfiles(PowerProfilesState next) {
    if (next == _state) return false;
    _state = next;
    notifyListeners();
    return true;
  }

  void _fail(PowerProfilesFailure e, {required bool status}) {
    final changed =
        _error != e.message ||
        _errorKind != e.kind ||
        (status && _status != PowerProfilesStatus.unavailable);
    _error = e.message;
    _errorKind = e.kind;
    if (status) _status = PowerProfilesStatus.unavailable;
    if (changed) notifyListeners();
  }

  Future<void> _readTuned({bool keepError = false}) async {
    try {
      final next = await _tuned.read();
      final changed =
          next != _tunedState || (!keepError && _tunedError.isNotEmpty);
      _tunedState = next;
      if (!keepError) _tunedError = '';
      if (changed) notifyListeners();
    } on TunedFailure catch (e) {
      if (e.kind == TunedFailureKind.unavailable) {
        // No TuneD is the common case, not an error: the section goes away.
        if (_tunedState == null) return;
        _tunedState = null;
        notifyListeners();
        return;
      }
      if (_tunedError == e.message) return;
      _tunedError = e.message;
      notifyListeners();
    }
  }

  Future<void> _readTuning() async {
    final next = await readPowerTuning(_sysfs);
    final edits = _edits.against(next);
    if (next == _tuning && edits == _edits) return;
    _tuning = next;
    _edits = edits;
    notifyListeners();
  }

  // --- writes ---------------------------------------------------------------

  /// Asks the daemon for [profile]. The pane's selection follows the daemon's
  /// answer, not the request.
  Future<void> setProfile(String profile) async {
    if (_pendingProfile != null || _state?.active == profile) return;
    _pendingProfile = profile;
    notifyListeners();
    try {
      await _profiles.setActiveProfile(profile);
      _error = '';
      _errorKind = null;
    } on PowerProfilesFailure catch (e) {
      _error = e.message;
      _errorKind = e.kind;
    } finally {
      _pendingProfile = null;
    }
    // Read back rather than trusting the write: a hold, a degraded mode or a
    // daemon that silently refused all show as what the daemon now says.
    await _readProfiles(keepError: true);
    notifyListeners();
  }

  Future<void> setBatteryAware(bool enabled) async {
    if (_pendingBatteryAware || _state?.batteryAware == null) return;
    _pendingBatteryAware = true;
    notifyListeners();
    try {
      await _profiles.setBatteryAware(enabled);
      _error = '';
      _errorKind = null;
    } on PowerProfilesFailure catch (e) {
      _error = e.message;
      _errorKind = e.kind;
    } finally {
      _pendingBatteryAware = false;
    }
    await _readProfiles(keepError: true);
    notifyListeners();
  }

  Future<void> switchTuned(String name) =>
      _tunedWrite(name, () => _tuned.switchProfile(name));

  /// Hands the choice back to TuneD (`tuned-adm auto_profile`).
  Future<void> useTunedRecommended() => _tunedWrite('', _tuned.useRecommended);

  Future<void> _tunedWrite(
    String pending,
    Future<void> Function() write,
  ) async {
    if (_pendingTuned != null) return;
    _pendingTuned = pending;
    notifyListeners();
    try {
      await write();
      _tunedError = '';
    } on TunedFailure catch (e) {
      _tunedError = e.message;
    } finally {
      _pendingTuned = null;
    }
    // A TuneD switch moves tuned-ppd's mode as well as the knobs.
    await Future.wait([
      _readTuned(keepError: true),
      _readProfiles(),
      _readTuning(),
    ]);
    notifyListeners();
  }

  // --- fine tuning ----------------------------------------------------------

  void _edit(PowerTuningEdits next) {
    final tuning = _tuning;
    final reconciled = tuning == null ? next : next.against(tuning);
    if (reconciled == _edits) return;
    _edits = reconciled;
    notifyListeners();
  }

  void setPlatformProfile(String value) =>
      _edit(_edits.copyWith(platformProfile: value));

  void setGovernor(String value) => _edit(_edits.copyWith(governor: value));

  void setEnergyPreference(String value) =>
      _edit(_edits.copyWith(energyPreference: value));

  void setBoost(bool value) => _edit(_edits.copyWith(boost: value));

  void setMaxFrequencyPercent(int value) =>
      _edit(_edits.copyWith(maxFrequencyPercent: value));

  /// Drops every unapplied edit.
  void discardTuning() {
    if (_edits.isEmpty && _tuningError == null) return;
    _edits = PowerTuningEdits.none;
    _tuningError = null;
    notifyListeners();
  }

  /// Writes every edit in one administrator prompt, then re-reads what the
  /// kernel actually took. An edit the kernel refused stays pending, so the
  /// pane still shows what was asked for beside the refusal.
  Future<void> applyTuning() async {
    final tuning = _tuning;
    if (_applying || tuning == null || _edits.isEmpty) return;
    final writes = planPowerTuning(tuning, _edits);
    _applying = true;
    _tuningError = null;
    notifyListeners();
    var succeeded = false;
    try {
      await _writer.write(writes);
      succeeded = true;
    } on SysfsWriteFailure catch (e) {
      _tuningError = e;
    } finally {
      _applying = false;
    }
    await _readTuning();
    if (succeeded) {
      // Whatever the kernel rounded — a frequency snapped to a step — is the
      // machine's answer, not an edit still waiting.
      _edits = PowerTuningEdits.none;
    }
    notifyListeners();
  }
}
