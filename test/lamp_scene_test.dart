// The lamp scene: the field is data and the same data everywhere, the geometry
// puts the lamp and the fortune in the card without either landing on the
// other, and the painter survives every size the grid can hand it.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/fortune/lamp_scene.dart';

/// Paints [field] at [size] and returns nothing — the assertion is that it did
/// not throw. A picture is the one thing a unit test cannot check, but "this
/// size does not divide by zero" is worth pinning across the range.
void _paint(LampField field, Size size,
    {double time = kLampStillMoment, double glow = 0}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  LampPainter(field: field, time: time, glow: glow).paint(canvas, size);
  recorder.endRecording().dispose();
}

void main() {
  group('LampField', () {
    test('is the same field for the same seed', () {
      // Fixed, so the smoke curls the same way on both monitors and across a
      // restart. A plume that reshuffled on every rebuild would be the most
      // distracting thing on the desktop.
      final a = LampField.build();
      final b = LampField.build();

      expect(a.puffs.map((p) => p.phase), b.puffs.map((p) => p.phase));
      expect(a.puffs.map((p) => p.radius), b.puffs.map((p) => p.radius));
      expect(a.stars.map((s) => s.x), b.stars.map((s) => s.x));
      expect(a.embers.map((e) => e.period), b.embers.map((e) => e.period));
    });

    test('is a different field for a different seed', () {
      final other = LampField.build(seed: 99);

      expect(
        other.puffs.map((p) => p.phase),
        isNot(LampField.build().puffs.map((p) => p.phase)),
      );
    });

    test('holds the counts the frame cost was chosen against', () {
      final field = LampField.build();

      expect(field.puffs, hasLength(LampField.puffCount));
      expect(field.embers, hasLength(LampField.emberCount));
      expect(field.stars, hasLength(LampField.starCount));
    });

    test('spreads the puffs across the climb rather than clumping them', () {
      // Uniform random phases clump, and a clump in a plume reads as the lamp
      // coughing. Evenly spaced then jittered: no two puffs share a stretch.
      final phases = LampField.build().puffs.map((p) => p.phase).toList()
        ..sort();

      for (var i = 1; i < phases.length; i++) {
        expect(phases[i] - phases[i - 1], greaterThan(0.01));
      }
    });

    test('keeps the stars out of the bottom of the card', () {
      // That is where the lamp and the readout are, and a star behind either
      // is a smudge.
      for (final star in LampField.build().stars) {
        expect(star.y, lessThan(0.7));
      }
    });
  });

  group('LampGeometry', () {
    test('puts the lamp in the bottom-right of the card', () {
      const card = Size(312, 204);
      final lamp = LampGeometry.forCard(card);

      expect(lamp.rect.right, lessThanOrEqualTo(card.width));
      expect(lamp.rect.bottom, lessThanOrEqualTo(card.height));
      expect(lamp.rect.left, greaterThan(card.width / 2));
      expect(lamp.rect.top, greaterThan(card.height / 3));
    });

    test('sizes the lamp against the shorter edge on a short wide card', () {
      // Taken from the width alone, a lamp on a 6x1 card would be taller than
      // the card and leave the fortune nowhere to go.
      final lamp = LampGeometry.forCard(const Size(600, 96));

      expect(lamp.rect.height, lessThan(96));
      expect(lamp.rect.width, lessThan(600 * 0.42));
    });

    test('puts the spout inside the lamp, at its top-left', () {
      final lamp = LampGeometry.forCard(const Size(312, 204));

      expect(lamp.rect.contains(lamp.spout), isTrue);
      expect(lamp.spout.dx, lessThan(lamp.rect.center.dx));
      expect(lamp.spout.dy, lessThan(lamp.rect.center.dy));
    });

    test('keeps the tap target on the lamp body', () {
      final lamp = LampGeometry.forCard(const Size(312, 204));

      expect(lamp.rect.contains(lamp.tapTarget.topLeft), isTrue);
      expect(lamp.rect.contains(lamp.tapTarget.bottomRight), isTrue);
    });

    group('textArea', () {
      test('sets the fortune above the lamp on a squarer card', () {
        const card = Size(312, 204);
        final lamp = LampGeometry.forCard(card);
        final area = lamp.textArea(card, padding: 14, reserve: 32);

        expect(area.bottom, lessThanOrEqualTo(lamp.rect.top));
        expect(area.width, greaterThan(card.width / 2));
      });

      test('sets it beside the lamp on a short wide card', () {
        // Above the lamp there is barely a line's worth of height; beside it
        // there is the whole card.
        const card = Size(600, 108);
        final lamp = LampGeometry.forCard(card);
        final area = lamp.textArea(card, padding: 14, reserve: 32);

        expect(area.right, lessThanOrEqualTo(lamp.rect.left));
        expect(area.height, greaterThan(card.height / 2));
      });

      test('refuses a column too narrow to set text in', () {
        // Beside the lamp on a narrow card is two words a line, which is a
        // ribbon rather than a paragraph.
        const card = Size(190, 400);
        final lamp = LampGeometry.forCard(card);
        final area = lamp.textArea(card, padding: 14, reserve: 32);

        expect(area.bottom, lessThanOrEqualTo(lamp.rect.top));
      });

      test('never answers a negative box, however small the card', () {
        for (final card in const [Size(60, 40), Size(20, 200), Size(1, 1)]) {
          final area = LampGeometry.forCard(card)
              .textArea(card, padding: 14, reserve: 32);
          expect(area.width, greaterThanOrEqualTo(0));
          expect(area.height, greaterThanOrEqualTo(0));
        }
      });
    });
  });

  group('LampPainter', () {
    test('paints at every size the grid can hand it', () {
      final field = LampField.build();

      for (final size in const [
        Size(150, 70), // the widget's own floor
        Size(312, 204), // the default 3x2
        Size(744, 396), // the largest span the registry allows
      ]) {
        expect(() => _paint(field, size), returnsNormally);
      }
    });

    test('paints a hovered lamp and a still one alike', () {
      final field = LampField.build();

      expect(() => _paint(field, const Size(312, 204), glow: 1),
          returnsNormally);
      expect(() => _paint(field, const Size(312, 204), time: 0),
          returnsNormally);
      expect(() => _paint(field, const Size(312, 204), time: 3599),
          returnsNormally);
    });

    test('does nothing at all for an empty box', () {
      expect(() => _paint(LampField.build(), Size.zero), returnsNormally);
    });

    test('repaints for a hover and for nothing else', () {
      // Nothing on this card animates, so an identical painter is never a
      // reason to paint again — the hover glow is the only input that moves.
      final field = LampField.build();
      final painter = LampPainter(field: field);

      expect(painter.shouldRepaint(LampPainter(field: field)), isFalse);
      expect(
        painter.shouldRepaint(LampPainter(field: field, glow: 1)),
        isTrue,
      );
    });

    test('the still moment is one the plume is mid-climb at', () {
      // Not a starting point but the whole picture: at zero the smoke is a stub
      // above the spout, and the card would read as a lamp that had only just
      // been lit.
      expect(kLampStillMoment, greaterThan(0));

      final field = LampField.build();
      final climbing = field.puffs.where((puff) {
        final u = ((kLampStillMoment / puff.period) + puff.phase) % 1.0;
        return u > 0.15 && u < 0.85;
      });

      expect(climbing.length, greaterThan(LampField.puffCount ~/ 2));
    });
  });
}
