// The geometry of input capture: which rectangles an application may put pointer
// barriers on, which of its barriers are acceptable, and when a push of the
// pointer has crossed one.
//
// Pure Dart — no Wayland, no D-Bus — because every rule here is a portal-contract
// rule a test can pin, and getting one wrong is the difference between a mouse
// that walks onto the next computer and one that is stolen whenever it nears a
// second monitor.

/// One zone — a monitor, in the compositor's logical coordinates, as `GetZones`
/// reports it.
class CaptureZone {
  const CaptureZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.connector,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// The output's connector name, for logging and for finding its surface
  /// again; not part of the zone's identity on the bus.
  final String? connector;

  int get right => x + width;
  int get bottom => y + height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is CaptureZone &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.connector == connector;

  @override
  int get hashCode => Object.hash(x, y, width, height, connector);

  @override
  String toString() => 'CaptureZone(${width}x$height+$x+$y $connector)';
}

/// Folds the compositor's outputs into the zone list: empty ones dropped, and
/// mirrored outputs — separate `wl_output`s at one origin and one size — reported
/// once, because two identical zones would let one barrier validate twice.
List<CaptureZone> zonesFrom(Iterable<CaptureZone> outputs) {
  final zones = <CaptureZone>[];
  for (final output in outputs) {
    if (output.isEmpty) continue;
    final duplicate = zones.any((z) =>
        z.x == output.x &&
        z.y == output.y &&
        z.width == output.width &&
        z.height == output.height);
    if (!duplicate) zones.add(output);
  }
  return zones;
}

/// Whether two zone lists describe the same layout — what decides whether a
/// change of outputs is a new zone set at all.
bool sameZones(List<CaptureZone> a, List<CaptureZone> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Which side of its zone a barrier is on.
enum BarrierEdge { left, right, top, bottom }

/// A barrier as an application asked for it.
class RequestedBarrier {
  const RequestedBarrier(this.id, this.x1, this.y1, this.x2, this.y2);

  final int id;
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  @override
  String toString() => 'RequestedBarrier($id: $x1,$y1 → $x2,$y2)';
}

/// A barrier that has been accepted: the zone edge it sits on, and the span
/// along that edge it covers, as an inclusive range of pixels.
class PlacedBarrier {
  const PlacedBarrier({
    required this.id,
    required this.zone,
    required this.edge,
    required this.from,
    required this.to,
  });

  final int id;
  final CaptureZone zone;
  final BarrierEdge edge;

  /// First and last pixel covered along the edge — y for a vertical barrier,
  /// x for a horizontal one.
  final int from;
  final int to;

  bool get vertical => edge == BarrierEdge.left || edge == BarrierEdge.right;

  /// The line itself: x for a vertical barrier, y for a horizontal one. Per the
  /// portal, a barrier sits on the *top or left* edge of its pixels, so a zone's
  /// right barrier is at `zone.x + zone.width`, one past its last column.
  int get line => switch (edge) {
        BarrierEdge.left => zone.x,
        BarrierEdge.right => zone.right,
        BarrierEdge.top => zone.y,
        BarrierEdge.bottom => zone.bottom,
      };

  @override
  bool operator ==(Object other) =>
      other is PlacedBarrier &&
      other.id == id &&
      other.zone == zone &&
      other.edge == edge &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(id, zone, edge, from, to);

  @override
  String toString() => 'PlacedBarrier($id ${edge.name} of $zone, $from..$to)';
}

/// `SetPointerBarriers`' validation: each barrier either lands on an outside
/// edge of exactly one zone, or its id is reported back as failed.
///
/// The rules, from the portal's documentation:
/// - horizontal or vertical, never diagonal (and a single point is neither);
/// - fully contained within one zone's edge — the far end may be either the
///   last pixel or one past it, since applications disagree on which the
///   inclusive wording means and the frontend's own test backend accepts both;
/// - on the *outside boundary of the union* of the zones. A barrier between
///   two side-by-side monitors would turn the walk from one to the other into a
///   capture, so it fails if any other zone covers the pixels just across it.
({List<PlacedBarrier> placed, List<int> failed}) placeBarriers(
  List<CaptureZone> zones,
  List<RequestedBarrier> requested,
) {
  final placed = <PlacedBarrier>[];
  final failed = <int>[];
  for (final barrier in requested) {
    final result = _place(zones, barrier);
    if (result == null) {
      failed.add(barrier.id);
    } else {
      placed.add(result);
    }
  }
  return (placed: placed, failed: failed);
}

PlacedBarrier? _place(List<CaptureZone> zones, RequestedBarrier b) {
  if (b.id == 0) return null;
  final vertical = b.x1 == b.x2;
  final horizontal = b.y1 == b.y2;
  if (vertical == horizontal) return null; // diagonal, or a point

  final from = vertical ? _min(b.y1, b.y2) : _min(b.x1, b.x2);
  final to = vertical ? _max(b.y1, b.y2) : _max(b.x1, b.x2);
  final line = vertical ? b.x1 : b.y1;

  for (final zone in zones) {
    final start = vertical ? zone.y : zone.x;
    final end = vertical ? zone.bottom : zone.right;
    // `to == end` is the one-past-the-end spelling; clamp it back onto the
    // zone so the span is pixels the edge actually has.
    if (from < start || to > end || from >= end) continue;
    final last = to == end ? end - 1 : to;

    final BarrierEdge edge;
    if (vertical && line == zone.x) {
      edge = BarrierEdge.left;
    } else if (vertical && line == zone.right) {
      edge = BarrierEdge.right;
    } else if (horizontal && line == zone.y) {
      edge = BarrierEdge.top;
    } else if (horizontal && line == zone.bottom) {
      edge = BarrierEdge.bottom;
    } else {
      continue;
    }

    final candidate = PlacedBarrier(
        id: b.id, zone: zone, edge: edge, from: from, to: last);
    if (_coveredBeyond(zones, candidate)) return null;
    return candidate;
  }
  return null;
}

/// Whether any zone other than the barrier's own covers a pixel immediately
/// across it within its span — which is what makes it an inside edge.
bool _coveredBeyond(List<CaptureZone> zones, PlacedBarrier barrier) {
  // The row or column of pixels just outside the zone.
  final across = switch (barrier.edge) {
    BarrierEdge.left => barrier.zone.x - 1,
    BarrierEdge.right => barrier.zone.right,
    BarrierEdge.top => barrier.zone.y - 1,
    BarrierEdge.bottom => barrier.zone.bottom,
  };
  for (final other in zones) {
    if (identical(other, barrier.zone)) continue;
    final (acrossStart, acrossEnd, spanStart, spanEnd) = barrier.vertical
        ? (other.x, other.right, other.y, other.bottom)
        : (other.y, other.bottom, other.x, other.right);
    if (across < acrossStart || across >= acrossEnd) continue;
    if (barrier.to >= spanStart && barrier.from < spanEnd) return true;
  }
  return false;
}

/// Where a push crossed a barrier, and which one.
class BarrierCrossing {
  const BarrierCrossing(this.barrier, this.x, this.y);

  final PlacedBarrier barrier;

  /// The logical cursor position the push would have reached, which per the
  /// portal may — and here always does — lie outside every zone: that is how
  /// the application learns which way the pointer left.
  final double x;
  final double y;
}

/// Whether a relative motion of ([dx], [dy]) from the global pointer position
/// ([x], [y]) pushes through one of [barriers].
///
/// The compositor clamps the cursor to the zone, so the position never itself
/// passes a barrier: what crosses is a push *outward* while the pointer is in
/// the last row or column of pixels before the line. Any outward push counts,
/// however small — a slow hand arrives a fraction of a pixel at a time, and each
/// of those fractions is clamped away, so waiting for a whole pixel of overshoot
/// would leave the barrier uncrossable at low speed.
///
/// The reported position is the push's destination, moved at least just past
/// the line, so the application never sees an activation that seems to have
/// stayed on this screen.
BarrierCrossing? crossingFor(
  Iterable<PlacedBarrier> barriers,
  double x,
  double y,
  double dx,
  double dy,
) {
  for (final barrier in barriers) {
    final line = barrier.line;
    final along = barrier.vertical ? y : x;
    if (along < barrier.from || along >= barrier.to + 1) continue;
    switch (barrier.edge) {
      case BarrierEdge.right:
        if (dx > 0 && x >= line - 1 && x < line) {
          return BarrierCrossing(barrier, _maxD(x + dx, line.toDouble()), y + dy);
        }
      case BarrierEdge.left:
        if (dx < 0 && x >= line && x < line + 1) {
          return BarrierCrossing(barrier, _minD(x + dx, line - 1.0), y + dy);
        }
      case BarrierEdge.bottom:
        if (dy > 0 && y >= line - 1 && y < line) {
          return BarrierCrossing(barrier, x + dx, _maxD(y + dy, line.toDouble()));
        }
      case BarrierEdge.top:
        if (dy < 0 && y >= line && y < line + 1) {
          return BarrierCrossing(barrier, x + dx, _minD(y + dy, line - 1.0));
        }
    }
  }
  return null;
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
double _minD(double a, double b) => a < b ? a : b;
double _maxD(double a, double b) => a > b ? a : b;
