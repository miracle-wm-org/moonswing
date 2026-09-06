// What Tux says, and which line he says today.
//
// Pure and Flutter-free — no widgets, no clock of its own; the day is a
// parameter. That is what makes "the same day always answers the same line" and
// "nobody sees a repeat until they have seen them all" plain unit tests.
//
// Four things a change here has to keep true:
//
// - **The line is a function of the local date and nothing else.** The desktop
//   surface is one FlutterView per monitor, so a line picked at random per build
//   would differ between displays and rewrite itself while being read.
// - **The walk is a full permutation, not a hash.** `ordinal % n` recites the
//   list in written order; a hash repeats a line two days running about once a
//   month. A stride coprime with the list length visits every entry once before
//   repeating any — see [_strideFor].
// - **The count is derived from UTC midnights.** Differencing two *local*
//   `DateTime`s measures elapsed time, and `inDays` truncates a 23-hour DST day
//   to 0 — so a spring-forward Sunday would repeat Saturday's greeting.
// - **Nothing here claims anything about the user.** These are the lines a friend
//   says on the way past, not affirmations asserting facts about somebody the
//   shell knows nothing about.

/// The nice thing itself: one per day, in a rotation nobody reaches the end of in
/// a month.
///
/// Kept deliberately short — the 1x1 card is the size this feature was asked for,
/// and a line needing three lines of a 96px square is a line nobody reads.
const List<String> kTuxGreetings = [
  'Whatever you finish today is enough.',
  'Nice to have you back at the keyboard.',
  'Today is allowed to be an ordinary day.',
  'You have got through every day so far.',
  'Small steps still count as steps.',
  'Go easy on yourself out there.',
  'The hard part is usually just starting.',
  'Someone is glad you are around today.',
  'You are allowed to take the slow route.',
  'Take the break before you need it.',
  'Your best today is a moving target.',
  'Curiosity counts as productivity.',
  'Drink some water at some point, please.',
  'The tricky bug will make sense later.',
  'You do not have to do all of it today.',
  'It is fine to leave things half-done.',
  'Good work rarely feels like good work.',
  'Stretch. Look at something far away.',
  'Being stuck is part of the process.',
  'You are further along than you think.',
  'Tomorrow gets its own set of problems.',
  'Ask the question. It is not a silly one.',
  'Rest is not something you have to earn.',
  'Progress beats perfect, most days.',
  'Delete something today. It will feel good.',
  'Nobody has it all figured out either.',
  'Leave a note for whoever reads this next.',
  'Nice hair today, by the way.',
  'The world is still turning. Good sign.',
  'Say the kind thing you were thinking.',
];

/// How Tux opens. Rotated on its own stride, so the whole greeting moves day to
/// day rather than a fixed hello over changing text.
///
/// None of these names a time of day: the greeting is fixed for the whole
/// calendar day and is as likely to be read at midnight as over breakfast, so a
/// `Morning` here is wrong more often than right — and making it right would mean
/// three more timers for a card whose reason for existing is that it wakes once.
const List<String> kTuxSalutations = [
  'Hello',
  'Hey there',
  'Good to see you',
  'Welcome back',
  'Look who it is',
  'Hi',
  'There you are',
  'Oh, hello',
];

/// What Tux is saying today: a greeting line, and the salutation above it.
///
/// No `@immutable` and no import to carry it: this file is plain Dart, with no
/// `package:flutter` and no `package:meta` behind it, which is what keeps the
/// rotation a unit test that needs no binding at all.
class TuxGreeting {
  const TuxGreeting({required this.salutation, required this.line});

  /// The opener, already carrying the user's name when one is known — `Hey
  /// there, Sam` rather than a bare `Hey there`. Built here rather than at the
  /// call site so the comma is spelled in exactly one place and the no-name
  /// case cannot grow a dangling one.
  final String salutation;

  /// The nice thing.
  final String line;

  /// The whole greeting as one sentence, for the layouts with no room to set
  /// the two apart — the 1x1 card's bubble.
  String get combined => '$salutation. $line';

  @override
  bool operator ==(Object other) =>
      other is TuxGreeting &&
      other.salutation == salutation &&
      other.line == line;

  @override
  int get hashCode => Object.hash(salutation, line);

  @override
  String toString() => 'TuxGreeting($salutation, $line)';
}

/// Today's greeting for [day], addressed to [name] when there is one.
///
/// [offset] steps to the next entry of both rotations without moving the day —
/// what a tap on Tux does. Deliberately not persisted: the day's own line is what
/// comes back after a restart, because that is what the feature promises.
TuxGreeting greetingForDay(
  DateTime day, {
  String name = '',
  int offset = 0,
  List<String> lines = kTuxGreetings,
  List<String> salutations = kTuxSalutations,
}) {
  final ordinal = dayOrdinal(day) + offset;
  final salutation = _pick(salutations, ordinal, 'Hello');
  final trimmed = name.trim();
  return TuxGreeting(
    salutation: trimmed.isEmpty ? salutation : '$salutation, $trimmed',
    line: _pick(lines, ordinal, ''),
  );
}

/// Days since the epoch, counted in whole calendar days.
///
/// The date's parts are re-read into a UTC midnight before differencing, so the
/// count moves by exactly one over a daylight-saving boundary and is unaffected
/// by which zone the machine is in.
int dayOrdinal(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).difference(_epoch).inDays;

final DateTime _epoch = DateTime.utc(1970);

/// The instant the greeting changes: the next local midnight after [now].
///
/// Built from the date's parts (`DateTime(y, m, d + 1)`) rather than by adding
/// 24 hours, for `month.dart`'s reason — the day the clocks change is 23 or 25
/// hours long, and an added day lands an hour either side of midnight.
DateTime nextRollover(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);

/// [list]'s entry for [ordinal], walked by a stride coprime with its length.
String _pick(List<String> list, int ordinal, String fallback) {
  if (list.isEmpty) return fallback;
  final n = list.length;
  // Dart's `%` on a negative left operand still answers in `[0, n)`, so a date
  // before the epoch — which nothing produces, but a hand-set clock could —
  // indexes rather than throws.
  return list[(ordinal * _strideFor(n)) % n];
}

/// A step through a list of [n] entries that visits every one before repeating.
///
/// Any stride coprime with [n] has that property; this takes the first at or above
/// the golden-ratio fraction of [n], the classic low-discrepancy choice — so
/// consecutive days land far apart and the order carries no trace of the written
/// one.
int _strideFor(int n) {
  if (n <= 2) return 1;
  var stride = (n * 0.6180339887498949).round().clamp(1, n - 1);
  while (_gcd(stride, n) != 1) {
    stride++;
    if (stride >= n) return 1;
  }
  return stride;
}

int _gcd(int a, int b) {
  while (b != 0) {
    final t = b;
    b = a % b;
    a = t;
  }
  return a;
}
