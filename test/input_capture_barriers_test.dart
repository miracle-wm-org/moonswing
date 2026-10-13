import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/input_capture/barriers.dart';

/// The portal-contract geometry of input capture: which barriers are accepted,
/// and when a push crosses one. The examples are the portal documentation's own
/// left-right dual-monitor layout.

const _left = CaptureZone(x: 0, y: 0, width: 1920, height: 1080, connector: 'DP-1');
const _right =
    CaptureZone(x: 1920, y: 0, width: 1920, height: 1080, connector: 'DP-2');
const _pair = [_left, _right];

List<int> _failed(List<CaptureZone> zones, List<RequestedBarrier> barriers) =>
    placeBarriers(zones, barriers).failed;

PlacedBarrier _placed(List<CaptureZone> zones, RequestedBarrier barrier) =>
    placeBarriers(zones, [barrier]).placed.single;

void main() {
  group('placeBarriers', () {
    test('accepts every outside edge the portal documentation lists', () {
      final barriers = [
        const RequestedBarrier(1, 0, 0, 1919, 0), // top of left
        const RequestedBarrier(2, 0, 1080, 1919, 1080), // bottom of left
        const RequestedBarrier(3, 1920, 0, 3839, 0), // top of right
        const RequestedBarrier(4, 1920, 1080, 3839, 1080), // bottom of right
        const RequestedBarrier(5, 0, 0, 0, 1079), // left of left
        const RequestedBarrier(6, 3840, 0, 3840, 1079), // right of right
      ];
      final result = placeBarriers(_pair, barriers);
      expect(result.failed, isEmpty);
      expect(result.placed.map((b) => b.edge), [
        BarrierEdge.top,
        BarrierEdge.bottom,
        BarrierEdge.top,
        BarrierEdge.bottom,
        BarrierEdge.left,
        BarrierEdge.right,
      ]);
      expect(result.placed[5].zone, _right);
    });

    test('refuses the edge the two monitors share, from either side', () {
      expect(
        _failed(_pair, [
          const RequestedBarrier(7, 1920, 0, 1920, 1079),
        ]),
        [7],
      );
    });

    test('accepts a one-past-the-end span and clamps it onto the zone', () {
      final placed =
          _placed(_pair, const RequestedBarrier(1, 3840, 0, 3840, 1080));
      expect(placed.from, 0);
      expect(placed.to, 1079);
    });

    test('normalises a barrier drawn end to start', () {
      final placed = _placed([_left], const RequestedBarrier(1, 1919, 0, 0, 0));
      expect((placed.from, placed.to), (0, 1919));
    });

    test('refuses diagonals, points, id 0 and lines off any edge', () {
      expect(
        _failed(_pair, [
          const RequestedBarrier(1, 0, 0, 10, 10),
          const RequestedBarrier(2, 5, 5, 5, 5),
          const RequestedBarrier(0, 0, 0, 0, 1079),
          const RequestedBarrier(3, 100, 0, 100, 1079), // inside a zone
          const RequestedBarrier(4, 0, 0, 0, 2000), // longer than the edge
        ]),
        [1, 2, 0, 3, 4],
      );
    });

    test('a partly-shared edge is refused only where something is across it',
        () {
      // A smaller monitor to the right, covering only the top half.
      const small = CaptureZone(x: 1920, y: 0, width: 800, height: 540);
      const zones = [_left, small];
      expect(_failed(zones, [const RequestedBarrier(1, 1920, 0, 1920, 600)]),
          [1]);
      expect(
          _failed(zones, [const RequestedBarrier(2, 1920, 540, 1920, 1079)]),
          isEmpty);
    });
  });

  group('zonesFrom', () {
    test('reports a mirrored pair once and drops an output with no size', () {
      final zones = zonesFrom([
        _left,
        const CaptureZone(x: 0, y: 0, width: 1920, height: 1080, connector: 'HDMI-1'),
        const CaptureZone(x: 0, y: 0, width: 0, height: 0),
        _right,
      ]);
      expect(zones, [_left, _right]);
    });
  });

  group('crossingFor', () {
    final right = _placed(_pair, const RequestedBarrier(6, 3840, 0, 3840, 1079));
    final left = _placed(_pair, const RequestedBarrier(5, 0, 0, 0, 1079));
    final top = _placed([_left], const RequestedBarrier(1, 0, 0, 1919, 0));

    test('an outward push from the last column crosses, and lands past it', () {
      final crossing = crossingFor([right], 3839.5, 500, 0.3, 1);
      expect(crossing?.barrier.id, 6);
      expect(crossing!.x, greaterThanOrEqualTo(3840));
      expect(crossing.y, 501);
    });

    test('a fast push reports how far it would have gone', () {
      final crossing = crossingFor([right], 3839, 500, 25, 0);
      expect(crossing!.x, 3864);
    });

    test('an inward push, or one short of the edge, does not', () {
      expect(crossingFor([right], 3839.5, 500, -3, 0), isNull);
      expect(crossingFor([right], 3830, 500, 5, 0), isNull);
    });

    test('outside the barrier\'s span does not', () {
      final half = _placed(
          _pair, const RequestedBarrier(9, 3840, 0, 3840, 499));
      expect(crossingFor([half], 3839.5, 700, 4, 0), isNull);
      expect(crossingFor([half], 3839.5, 499.9, 4, 0), isNotNull);
    });

    test('left and top barriers report positions before the line', () {
      final l = crossingFor([left], 0.2, 10, -2, 0);
      expect(l!.x, lessThan(0));
      final t = crossingFor([top], 50, 0.5, 0, -0.1);
      expect(t!.y, lessThan(0));
    });
  });
}
