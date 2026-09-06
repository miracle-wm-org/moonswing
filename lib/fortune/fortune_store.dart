// The fortune, for the whole shell: one fork, however many surfaces draw it.
//
// `WeatherStore`'s singleton-`ChangeNotifier`-with-leases shape, minus the timer.
// Two differences follow from what a fortune *is*:
//
// - **Nothing polls.** A fortune is not a reading of anything — it does not go
//   stale, and one that replaced itself on a cadence would silently throw away
//   the line the user was in the middle of reading. It is fetched once, when the
//   first surface asks, and thereafter only when somebody presses the button.
// - **The lease still matters.** The desktop surface is one FlutterView per
//   monitor, so without a store this would be one fork per display showing a
//   different fortune on each — and a two-monitor user pressing refresh on one
//   card would watch the other not move.
//
// Flutter-free apart from `ChangeNotifier`, so the whole of this is a unit test.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/fortune/fortune_reader.dart';

class FortuneStore extends ChangeNotifier {
  FortuneStore._({FortuneReader? reader}) : _reader = reader ?? FortuneReader();

  static final FortuneStore instance = FortuneStore._();

  /// A detached store with an injected reader, so a widget test can take a real
  /// lease without forking anything. Offline in the same sense
  /// `WeatherStore.forTesting` is: nothing here spawns a process unless
  /// [reader]'s runner does.
  @visibleForTesting
  factory FortuneStore.forTesting({required FortuneReader reader}) =>
      FortuneStore._(reader: reader);

  final FortuneReader _reader;

  // --- published state -----------------------------------------------------

  String _text = '';

  /// The fortune on screen, or empty before the first one lands.
  String get text => _text;

  bool get hasFortune => _text.isNotEmpty;

  bool _loading = true;

  /// Whether a fetch is in flight *and there is nothing to show yet*.
  ///
  /// A refresh over an existing fortune deliberately does not report as loading:
  /// replacing the card's contents with a spinner for the handful of milliseconds
  /// a fork takes is a flash, not feedback.
  bool get loading => _loading && !hasFortune;

  String _error = '';

  /// Why there is no fortune, or empty. Set on every failed read.
  String get error => _error;

  bool _commandMissing = false;

  /// Whether the failure was "no `fortune` on this machine", which is the one
  /// the user can act on and the one the card offers a hint for.
  bool get commandMissing => _commandMissing;

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  bool _inFlight = false;
  bool _disposed = false;

  /// Take a lease. The *first* one fetches, so the fortune is on screen as soon
  /// as the desktop is — this is the "when you start the shell" half — and a
  /// second monitor's surface joining later shows the same one rather than
  /// forking for its own.
  void acquire() {
    _leases++;
    if (_leases == 1 && !hasFortune) unawaited(refresh());
  }

  void release() {
    if (_leases > 0) _leases--;
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get fetching => _inFlight;

  // --- the work ------------------------------------------------------------

  /// Fetch a new fortune. What the refresh button calls, and what the first lease
  /// calls.
  ///
  /// Nothing is notified at the *start* of a fetch, which is what makes this safe
  /// to call from [acquire] — that runs inside the acquiring widget's `initState`,
  /// and a synchronous `notifyListeners` from there is a `setState` on every other
  /// surface already holding a lease, during a build.
  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    _loading = true;
    try {
      final text = await _reader.read();
      _text = text;
      _error = '';
      _commandMissing = false;
    } on FortuneUnavailable catch (e) {
      // The previous fortune stays on screen: it is as good as it ever was, and
      // the error line says why there is no new one. `WeatherStore`'s rule.
      _error = e.message;
      _commandMissing = e.missing;
    } catch (e) {
      _error = 'Could not read a fortune';
      _commandMissing = false;
      debugPrint('fortune: $e');
    } finally {
      _loading = false;
      _inFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Seeds a store for a widget test, with no reader behind it.
  @visibleForTesting
  void seed({
    String text = '',
    String error = '',
    bool commandMissing = false,
    bool loading = false,
  }) {
    _text = text;
    _error = error;
    _commandMissing = commandMissing;
    _loading = loading;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
