// What Tux is saying, for the whole shell: one greeting however many surfaces
// draw it, and one timer behind all of them.
//
// `FortuneStore`'s singleton-`ChangeNotifier`-with-leases shape. The desktop
// surface is one FlutterView per monitor, so without a store a two-monitor user
// would be greeted by two penguins saying different things.
//
// Four things a change here has to keep true:
//
// - **The greeting is derived, never stored.** [greeting] is
//   `greetingForDay(today)` and nothing else, so there is no state to get out of
//   step with the clock and a restart brings back the same line.
// - **The timer exists only while somebody is looking, and it is a one-shot.**
//   `TimersStore._syncTicker`'s rule. It fires once at the next local midnight
//   rather than ticking: the thing being waited for happens once a day.
// - **The rollover instant is built from the date's parts** (`nextRollover`),
//   because the day the clocks change is 23 or 25 hours long and
//   `add(Duration(days: 1))` lands an hour either side of midnight.
// - **`acquire` notifies nothing.** It runs inside the acquiring widget's
//   `initState`, and a synchronous `notifyListeners` from there is a `setState`
//   on every other surface already holding a lease, during a build.
//
// Flutter-free apart from `ChangeNotifier`, like the other stores.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/lock/user_identity.dart';
import 'package:moonswing/tux/tux_greetings.dart';

/// Who to greet, resolved once.
///
/// The account's GECOS name, which is the display name the rest of the desktop
/// shows — `lock/user_identity.dart` already reads it, and a second place to ask
/// would be a second place to be wrong. Falls back to the account name and then
/// to nothing at all: a bare `Hello` is the correct greeting for a machine whose
/// passwd entry says nothing about a person.
String defaultGreetedName() {
  try {
    return tidyGreetedName(UserIdentity.current().displayName);
  } catch (_) {
    // `UserIdentity` catches its own failures, but it opens `libc` through
    // `dart:ffi` and a host that cannot (a bare test runner, an unusual build)
    // would throw out of the lookup rather than out of the read. A greeting is
    // not worth taking a desktop surface down for.
    return '';
  }
}

/// The part of a display name Tux says out loud.
///
/// The first word only: `Hey there, Alex` is a greeting and `Hey there, Alex
/// Fernandez-Whitmore` is a summons. An all-lowercase account name is
/// capitalised, because `Hello, sam` reads as a shell echoing a variable.
String tidyGreetedName(String displayName) {
  final first = displayName.trim().split(RegExp(r'\s+')).first.trim();
  if (first.isEmpty) return '';
  // Long enough to be a login rather than a name, or carrying punctuation an
  // account name has and a person does not — say nothing rather than something
  // odd.
  if (first.length > 16 || !RegExp(r"^[\p{L}][\p{L}'’-]*$", unicode: true).hasMatch(first)) {
    return '';
  }
  return first[0].toUpperCase() + first.substring(1);
}

class TuxStore extends ChangeNotifier {
  TuxStore._({
    DateTime Function()? now,
    String Function()? name,
    List<String>? lines,
    List<String>? salutations,
  })  : _now = now ?? DateTime.now,
        _name = name ?? defaultGreetedName,
        _lines = lines ?? kTuxGreetings,
        _salutations = salutations ?? kTuxSalutations;

  static final TuxStore instance = TuxStore._();

  /// A detached store on an injected clock and name, so a widget test can take a
  /// real lease, name the day it is pretending to be, and never touch `libc` or
  /// arm a timer that outlives the test.
  ///
  /// [resolveName] is the same seam one level down, for the one test that counts
  /// how many times the passwd database is asked — a `getpwuid` per monitor is
  /// what [greetedName]'s memoisation exists to prevent.
  @visibleForTesting
  factory TuxStore.forTesting({
    required DateTime Function() now,
    String name = '',
    String Function()? resolveName,
    List<String>? lines,
    List<String>? salutations,
  }) =>
      TuxStore._(
        now: now,
        name: resolveName ?? () => name,
        lines: lines,
        salutations: salutations,
      );

  final DateTime Function() _now;
  final String Function() _name;
  final List<String> _lines;
  final List<String> _salutations;

  // --- published state -----------------------------------------------------

  String? _resolvedName;

  /// The name in the salutation, or empty. Resolved on the first lease and kept
  /// — the passwd entry does not change under a running session, and asking
  /// again per surface would be one `getpwuid` per monitor.
  String get greetedName => _resolvedName ??= _name();

  int _offset = 0;

  /// How many times [another] has been pressed since the day turned over.
  ///
  /// Deliberately not persisted and deliberately reset by the rollover: the
  /// day's *own* line is what the feature promises, and it is what comes back
  /// tomorrow however far somebody stepped through the list today.
  @visibleForTesting
  int get offset => _offset;

  /// What Tux is saying.
  TuxGreeting get greeting => greetingForDay(
        _now(),
        name: greetedName,
        offset: _offset,
        lines: _lines,
        salutations: _salutations,
      );

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  Timer? _rollover;

  /// Take a lease. The first one resolves the name and arms the rollover;
  /// nothing here notifies.
  void acquire() {
    _leases++;
    if (_leases == 1) {
      greetedName;
      _armRollover();
    }
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _rollover?.cancel();
      _rollover = null;
    }
  }

  @visibleForTesting
  int get leaseCount => _leases;

  @visibleForTesting
  bool get waitingForRollover => _rollover != null;

  // --- the interaction -----------------------------------------------------

  /// Step to the next line without moving the day — what a tap on Tux does.
  ///
  /// A greeting is a nice thing to be handed once, and somebody who wants another
  /// should not have to wait until tomorrow. No animation on the change, for the
  /// fortune card's reason: it would be the only moving thing on a still card,
  /// moving exactly when the user has asked to read something.
  void another() {
    _offset++;
    notifyListeners();
  }

  void _armRollover() {
    _rollover?.cancel();
    final now = _now();
    var wait = nextRollover(now).difference(now);
    // A clock stepped forward past the instant we computed, or a zone whose
    // rules put midnight behind us: wait a minute and ask again rather than
    // scheduling a zero-length timer that spins.
    if (wait <= Duration.zero) wait = const Duration(minutes: 1);
    _rollover = Timer(wait, _onRollover);
  }

  void _onRollover() {
    _offset = 0;
    _armRollover();
    notifyListeners();
  }

  /// Fires the rollover now, as though the day had turned over. Tests only —
  /// the alternative is a test that waits until midnight.
  @visibleForTesting
  void rollOverNow() => _onRollover();

  @override
  void dispose() {
    _rollover?.cancel();
    _rollover = null;
    super.dispose();
  }
}
