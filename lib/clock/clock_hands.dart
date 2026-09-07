// Where an analog clock's hands point, and how much furniture its dial can
// carry — the pure half of the analog clock, with no Flutter and no clock of
// its own.
//
// `moon_phase.dart`'s shape one floor down: every entry point takes the instant
// it is asked about, so the geometry is a unit test rather than something only a
// running desktop can check. `MinuteClockStore` is the only thing in the feature
// that knows what time it is.
//
// **There is no second hand, and no room left for one.** A hand that sweeps
// seconds is a repaint a second on a surface with no repaint boundary above it,
// forever, on every monitor — which is the one thing a desktop widget must not
// cost. So [ClockHands] is built from the hour and the minute alone, and a face
// drawn from it is still true a moment later.

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A full turn, in radians. Named because every angle here is a *fraction of a
/// turn* and this is the only place the two units meet.
const double _turn = 2 * math.pi;

/// Where the two hands point, as fractions of a turn clockwise from twelve.
///
/// Turns rather than radians because that is the unit the dial is laid out in —
/// an hour is a twelfth, a minute a sixtieth — and a fraction is the same
/// number whichever way the painter chooses to rotate.
class ClockHands {
  const ClockHands({required this.hourTurns, required this.minuteTurns});

  /// The hands at [time], to the minute.
  ///
  /// The hour hand carries the minutes with it (it is a third of the way past
  /// the four at twenty past), because an hour hand that jumps between numerals
  /// reads as a broken clock. The minute hand does *not* carry the seconds: it
  /// steps once a minute, which is the whole point — see the header.
  factory ClockHands.at(DateTime time) {
    final minutes = time.minute / 60;
    return ClockHands(
      // `hour % 12`, so noon and midnight both point straight up rather than
      // the hand running off the end of the dial through the afternoon.
      hourTurns: (time.hour % 12 + minutes) / 12,
      minuteTurns: minutes,
    );
  }

  /// Clockwise from twelve o'clock: 0 is straight up, 0.25 is three o'clock.
  final double hourTurns;
  final double minuteTurns;

  double get hourRadians => hourTurns * _turn;
  double get minuteRadians => minuteTurns * _turn;

  @override
  bool operator ==(Object other) =>
      other is ClockHands &&
      other.hourTurns == hourTurns &&
      other.minuteTurns == minuteTurns;

  @override
  int get hashCode => Object.hash(hourTurns, minuteTurns);

  @override
  String toString() =>
      'ClockHands(hour: $hourTurns turns, minute: $minuteTurns turns)';
}

/// The unit vector [turns] clockwise from twelve o'clock.
///
/// In screen coordinates — x to the right, **y down** — which is why twelve is
/// negative y and the sine and cosine are the opposite way round from the pair
/// a maths text would write.
Offset clockDirection(double turns) {
  final angle = turns * _turn;
  return Offset(math.sin(angle), -math.cos(angle));
}

/// The dial radius, in logical pixels, at which the sixty minute marks start
/// being drawn.
///
/// Below it they are sub-pixel lines a hair apart, which rasters as a grey ring
/// rather than as marks — worse than the bare dial the widget draws instead. A
/// 1x1 card on the default grid is a 96px cell, so its face lands under this and
/// takes the twelve hour marks alone; two cells clears it comfortably.
const double kMinuteTickDialRadius = 46;

/// The dial radius at which the hour numerals are set inside the marks.
///
/// Chosen from the type, not the picture: the numerals are [kNumeralHeightRatio]
/// of the radius, so this is the radius at which `10` and `11` are still legible
/// rather than a smudge, and it is comfortably clear of a 2x2 card.
const double kNumeralDialRadius = 66;

/// The numerals' font size as a fraction of the dial's radius.
///
/// Here rather than in the painter because it is what [kNumeralDialRadius] is
/// derived from, and the two drifting apart is how a threshold stops meaning
/// anything.
const double kNumeralHeightRatio = 0.185;

/// How much furniture a dial of a given size can usefully carry.
///
/// A desktop widget is resized by the user from one cell to several, and a face
/// is a picture whose detail has to earn its pixels: sixty marks on a 70px dial
/// is mud, and numerals under it are illegible rather than small.
enum ClockDialDetail {
  /// The twelve hour marks and the hands. What a one-cell card draws.
  hours,

  /// The hour marks with the sixty minute marks between them.
  minutes,

  /// The marks with the hour numerals set inside them.
  numerals;

  bool get hasMinuteTicks => this != ClockDialDetail.hours;
  bool get hasNumerals => this == ClockDialDetail.numerals;

  /// What a dial of [radius] logical pixels carries.
  static ClockDialDetail forRadius(double radius) {
    if (radius >= kNumeralDialRadius) return ClockDialDetail.numerals;
    if (radius >= kMinuteTickDialRadius) return ClockDialDetail.minutes;
    return ClockDialDetail.hours;
  }
}
