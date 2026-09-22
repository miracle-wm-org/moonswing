import 'package:flutter/foundation.dart';

import 'package:moonswing/power/power_config.dart';
import 'package:moonswing/power/power_inhibitor.dart';

/// Decides when the shell holds logind's power-key inhibitor — the *and* of the
/// two things that have to be true for the shell to answer the button at all.
///
/// Neither half is enough on its own:
///
/// * **The compositor has to deliver the key.** Registration goes through
///   `ext-input-trigger`, which a compositor that is not a recent Mir does not
///   advertise, and a combination another client owns is refused. Either way the
///   press never reaches the shell — and a shell that had inhibited logind anyway
///   would have turned the power button into a key that does nothing at all.
///   [setKeyOwned] is the compositor's answer, and the lock waits for it.
/// * **The user has to want it.** `[power] key_action = "none"` hands the key
///   back, and `inhibit_logind = false` says `HandlePowerKey` is already `ignore`.
///   Both arrive through [setConfig], which the root calls on every live config
///   change, so turning the feature off releases the lock rather than waiting for
///   a restart.
///
/// A singleton with the shell's other start-up stores: the two callers are a
/// Wayland-layer service and the widget root, which have no path to each other.
class PowerKeyService {
  PowerKeyService._({PowerInhibitor? inhibitor})
      : _inhibitor = inhibitor ?? LogindPowerInhibitor();

  static final PowerKeyService instance = PowerKeyService._();

  /// A service over a fake inhibitor. A unit test must never take a real one:
  /// it would change what the machine running the test does when somebody
  /// presses its power button.
  @visibleForTesting
  factory PowerKeyService.forTesting({required PowerInhibitor inhibitor}) =>
      PowerKeyService._(inhibitor: inhibitor);

  final PowerInhibitor _inhibitor;

  PowerConfig _config = const PowerConfig();
  bool _keyOwned = false;

  /// Whether [setConfig] has ever been called — that is, whether [_config] is the
  /// user's or merely the built-in default.
  ///
  /// The third condition on the lock, and it exists because the two inputs arrive
  /// from services that race: `startPowerService` publishes the config on its own
  /// event-loop turn while the compositor answers the registration after a
  /// Wayland round trip. The order is all but fixed in practice, and "all but" is
  /// how a machine whose config says `inhibit_logind = false` would take a lock
  /// for a moment anyway, on the strength of a default the user had overridden.
  bool _configured = false;

  /// Serializes [_reconcile]: taking and releasing the lock are both round
  /// trips to logind, and a config edit landing mid-flight would otherwise
  /// interleave a take with a release and leave the lock in whichever state
  /// finished last rather than the one that was asked for.
  Future<void> _settled = Future<void>.value();

  /// Why the last take or release failed, or null. Not a [ServiceStatus]:
  /// this can move long after start-up, when the user flips the setting.
  String? get lastError => _lastError;
  String? _lastError;

  /// The config the service is currently reconciled against.
  @visibleForTesting
  PowerConfig get config => _config;

  /// Whether the inhibitor should be held right now.
  @visibleForTesting
  bool get wantsInhibitor =>
      _configured && _keyOwned && _config.inhibitsLogind;

  /// Whether it actually is.
  @visibleForTesting
  bool get isInhibiting => _inhibitor.isHeld;

  /// The compositor answered the power-key registration: true once the shell
  /// owns the combination, false when it was refused, became unavailable, or
  /// was never registered at all.
  Future<void> setKeyOwned(bool owned) {
    if (owned == _keyOwned) return _settled;
    _keyOwned = owned;
    return _reconcile();
  }

  /// The live `[power]` config. Cheap to call on every notify: an unchanged
  /// config is compared away rather than re-round-tripping to logind.
  Future<void> setConfig(PowerConfig config) {
    // The first call always reconciles, even when it hands over a config equal
    // to the built-in default: it is what arms [_configured], and until it
    // lands the shell holds nothing.
    if (_configured && config == _config) return _settled;
    _configured = true;
    _config = config;
    return _reconcile();
  }

  Future<void> _reconcile() {
    return _settled = _settled.then((_) async {
      if (wantsInhibitor == _inhibitor.isHeld) return;
      try {
        if (wantsInhibitor) {
          await _inhibitor.take();
        } else {
          await _inhibitor.release();
        }
        _lastError = null;
      } catch (e) {
        // Recorded rather than rethrown out of the chain: a throw here would
        // poison [_settled] for every later reconcile, and the *first* attempt
        // is the one whose failure the caller sees (see [startPowerService]).
        _lastError = '$e';
        debugPrint('power: could not ${wantsInhibitor ? 'take' : 'release'} '
            'the logind inhibitor: $e');
      }
    });
  }

  /// Gives the lock back, whatever the config says. For shell teardown.
  Future<void> shutdown() {
    _keyOwned = false;
    _config = const PowerConfig(keyAction: PowerKeyAction.none);
    return _reconcile();
  }
}

/// Start-up task for [ShellService.power]: publishes the `[power]` config to
/// the service, so that the inhibitor is taken as soon as the compositor
/// confirms the trigger.
///
/// It normally settles [ServiceStatus.ready] without having taken anything —
/// the compositor's answer to the registration arrives on the Wayland
/// service's own schedule, and [PowerKeyService.setKeyOwned] is what acts on
/// it. That is the honest status for what this task can know at the time it
/// runs: nothing here is being waited on by a loader, and a lock the shell
/// cannot take *yet* is not a lock it has failed to take. A failure that lands
/// afterwards is logged and kept in [PowerKeyService.lastError]; the visible
/// consequence is the one the power menu cannot hide, which is logind powering
/// the machine off on a press.
Future<void> startPowerService(PowerConfig config) async {
  await PowerKeyService.instance.setConfig(config);
  final error = PowerKeyService.instance.lastError;
  if (error != null) throw StateError(error);
}
