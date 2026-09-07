// The clock face, drawn.
//
// A painter and not a picture for the reason `moon_render.dart` gives: the shell
// ships no image assets at all — no `assets:` section, themes embedded as
// constants, wallpapers found by path — so the first binary asset would mean the
// Flutter bundle, the Makefile and the snap all growing a case for one. A dial
// is a dozen lines and two hands anyway, and a drawn one takes the user's theme
// where an image would take whatever palette it was exported with.
//
// Three things a change here has to keep true:
//
// - **Every length is a fraction of the radius.** The card is resized by the
//   user from one cell to several, so a literal pixel here is a hand that is
//   right at one size and wrong at every other. The ratios are named below.
// - **The face's detail is bought at the size it has** — see [ClockDialDetail].
//   Sixty marks on a small dial rasters as a grey ring, and numerals under it
//   are illegible rather than small.
// - **Nothing here animates, and nothing here draws seconds.** This painter can
//   sit on a desktop for weeks; it is asked to paint when the minute changes and
//   at no other time, which is what makes a widget with no repaint boundary
//   above it affordable in the first place.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/clock/clock_hands.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_config.dart';

// --- the ratios ------------------------------------------------------------
//
// All of them fractions of the dial's radius, and all of them here rather than
// inline so the face can be re-proportioned in one place.

/// The rim's stroke width.
const double _rimWidth = 0.02;

/// Where the marks start, measured from the centre outwards.
const double _markOuter = 0.97;

/// Where the minute marks stop, and the two lengths an hour mark takes — the
/// shorter one when there are numerals inside it to leave room for.
const double _minuteMarkInner = 0.92;
const double _hourMarkInner = 0.82;
const double _hourMarkInnerWithNumerals = 0.88;

/// The circle the numerals are centred on.
const double _numeralRing = 0.75;

/// The hands: how far each reaches past the centre, and how far it overhangs
/// behind it. The tail is what makes a pair of lines read as a clock's hands
/// rather than as a wedge.
const double _hourHandLength = 0.50;
const double _minuteHandLength = 0.76;
const double _handTail = 0.13;

/// The hands' widths, and the cap over their pivot.
const double _hourHandWidth = 0.075;
const double _minuteHandWidth = 0.05;
const double _capRadius = 0.05;

/// The colours a face is drawn in, resolved from the theme.
///
/// A value object rather than six parameters so [ClockFacePainter.shouldRepaint]
/// is one comparison, and so a theme edit that moves one colour is the only
/// thing that can make it answer true.
@immutable
class ClockFacePalette {
  const ClockFacePalette({
    required this.face,
    required this.rim,
    required this.marks,
    required this.minuteMarks,
    required this.numerals,
    required this.hands,
    required this.cap,
  });

  /// The theme's own dial.
  ///
  /// The face sits on a `PopupCard`, so it takes the theme's control surface
  /// rather than a colour of its own — the same shade every other inset surface
  /// in the shell uses — and the marks and hands are the ordinary foreground on
  /// top of it. Only the cap is the accent: it is the one part of a clock face
  /// that is traditionally coloured, and it is small enough to be a highlight
  /// rather than a wash.
  factory ClockFacePalette.of(ThemeConfig theme) => ClockFacePalette(
        face: theme.controlSurface,
        rim: theme.divider,
        marks: theme.foreground,
        minuteMarks: theme.foreground.withValues(alpha: 0.45),
        numerals: theme.foreground.withValues(alpha: 0.8),
        hands: theme.foreground,
        cap: theme.accent,
      );

  final Color face;
  final Color rim;
  final Color marks;
  final Color minuteMarks;
  final Color numerals;
  final Color hands;
  final Color cap;

  @override
  bool operator ==(Object other) =>
      other is ClockFacePalette &&
      other.face == face &&
      other.rim == rim &&
      other.marks == marks &&
      other.minuteMarks == minuteMarks &&
      other.numerals == numerals &&
      other.hands == hands &&
      other.cap == cap;

  @override
  int get hashCode =>
      Object.hash(face, rim, marks, minuteMarks, numerals, hands, cap);
}

/// The dial, its marks and its two hands.
class ClockFacePainter extends CustomPainter {
  const ClockFacePainter({
    required this.hands,
    required this.palette,
    this.detail,
    this.fontFamily,
  });

  final ClockHands hands;
  final ClockFacePalette palette;

  /// What the dial carries, or null to let the size decide — which is what the
  /// widget does. Resolved at paint time rather than measured in a
  /// `LayoutBuilder` above: a rebuild inside one marks it needing layout, and a
  /// relayout steps straight over the repaint boundary nested inside it, so the
  /// minute turning over would re-record the whole desktop surface.
  final ClockDialDetail? detail;

  /// The theme's font, so the numerals are set in the same face as the rest of
  /// the shell rather than in the platform default.
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    // Defensive rather than decorative: the widget hands over a square, but a
    // painter given a rectangle should draw a circle inside it rather than an
    // oval overhanging one edge.
    final centre = size.center(Offset.zero);
    final outer = math.min(size.width, size.height) / 2;
    if (outer <= 0) return;

    final rim = math.max(1.0, outer * _rimWidth);
    final radius = outer - rim / 2;
    final detail = detailFor(radius);

    canvas.drawCircle(centre, radius, Paint()..color = palette.face);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = palette.rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim,
    );

    if (detail.hasMinuteTicks) {
      _paintMarks(
        canvas,
        centre: centre,
        radius: radius,
        // The twelve hour positions are skipped rather than drawn over: a
        // minute mark under an hour mark is a darker hour mark wherever either
        // colour is translucent.
        positions: [for (var i = 0; i < 60; i++) if (i % 5 != 0) i / 60],
        inner: _minuteMarkInner,
        width: math.max(0.75, radius * 0.012),
        color: palette.minuteMarks,
      );
    }

    _paintMarks(
      canvas,
      centre: centre,
      radius: radius,
      positions: [for (var i = 0; i < 12; i++) i / 12],
      inner: detail.hasNumerals ? _hourMarkInnerWithNumerals : _hourMarkInner,
      width: math.max(1.5, radius * 0.03),
      color: palette.marks,
    );

    if (detail.hasNumerals) _paintNumerals(canvas, centre, radius);

    _paintHand(
      canvas,
      centre: centre,
      radius: radius,
      turns: hands.hourTurns,
      length: _hourHandLength,
      width: math.max(2.0, radius * _hourHandWidth),
    );
    _paintHand(
      canvas,
      centre: centre,
      radius: radius,
      turns: hands.minuteTurns,
      length: _minuteHandLength,
      width: math.max(1.5, radius * _minuteHandWidth),
    );

    canvas.drawCircle(
      centre,
      math.max(2.0, radius * _capRadius),
      Paint()..color = palette.cap,
    );
  }

  /// One stroked path of many subpaths rather than one stroke per mark — the
  /// economy `moon_render.dart` states for its ray systems, and the difference
  /// between one draw call and sixty.
  void _paintMarks(
    Canvas canvas, {
    required Offset centre,
    required double radius,
    required List<double> positions,
    required double inner,
    required double width,
    required Color color,
  }) {
    final path = Path();
    for (final turns in positions) {
      final direction = clockDirection(turns);
      path
        ..moveTo(
          centre.dx + direction.dx * radius * _markOuter,
          centre.dy + direction.dy * radius * _markOuter,
        )
        ..lineTo(
          centre.dx + direction.dx * radius * inner,
          centre.dy + direction.dy * radius * inner,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width,
    );
  }

  void _paintNumerals(Canvas canvas, Offset centre, double radius) {
    final style = TextStyle(
      fontFamily: fontFamily,
      fontSize: radius * kNumeralHeightRatio,
      fontWeight: FontWeight.w500,
      height: 1,
      color: palette.numerals,
    );

    for (var hour = 1; hour <= 12; hour++) {
      final painter = TextPainter(
        text: TextSpan(text: '$hour', style: style),
        textDirection: TextDirection.ltr,
        // Deliberately unscaled, and the one place in the shell that says so
        // out loud: the numerals are dial furniture sized by the radius, the
        // way `ShellSizes` names pointer boxes rather than glyphs. The theme's
        // `font_size` growing the type is not an instruction to push `11` off
        // the edge of the clock.
        textScaler: TextScaler.noScaling,
      )..layout();

      final direction = clockDirection(hour / 12);
      final at = centre + direction * radius * _numeralRing;
      painter.paint(
        canvas,
        at - Offset(painter.width / 2, painter.height / 2),
      );
      painter.dispose();
    }
  }

  void _paintHand(
    Canvas canvas, {
    required Offset centre,
    required double radius,
    required double turns,
    required double length,
    required double width,
  }) {
    final direction = clockDirection(turns);
    canvas.drawLine(
      centre - direction * radius * _handTail,
      centre + direction * radius * length,
      Paint()
        ..color = palette.hands
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width,
    );
  }

  /// What a dial of [radius] carries: the override if one was given, and
  /// otherwise whatever the size can hold.
  ClockDialDetail detailFor(double radius) =>
      detail ?? ClockDialDetail.forRadius(radius);

  @override
  bool shouldRepaint(ClockFacePainter oldDelegate) =>
      oldDelegate.hands != hands ||
      oldDelegate.detail != detail ||
      oldDelegate.palette != palette ||
      oldDelegate.fontFamily != fontFamily;
}

/// A clock face filling the box it is given, in the ambient theme.
///
/// Square by construction and centred in whatever rectangle the parent hands
/// over, with **no `LayoutBuilder`**: the dial's size comes out of ordinary
/// layout and its detail is chosen by the painter from the radius it is handed.
/// A builder here would be measured every time the minute moved, and a relayout
/// is the one thing the repaint boundary below cannot contain.
///
/// The theme is read here rather than passed in, so a face on screen restyles
/// with the rest of the shell — `ThemeProvider`'s reason for existing. The
/// boundary is its own, because the desktop surface has none: without it the
/// minute turning over re-records the whole surface picture and damages the
/// whole output.
class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.hands, this.detail});

  final ClockHands hands;

  /// What the dial carries. Defaults to whatever its size can hold; a caller
  /// passes one to pin a layout in a test.
  final ClockDialDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: ClockFacePainter(
              hands: hands,
              detail: detail,
              palette: ClockFacePalette.of(theme),
              fontFamily: theme.fontFamily,
            ),
          ),
        ),
      ),
    );
  }
}
