import 'package:flutter_test/flutter_test.dart';

/// Taps each corner of [finder]'s box, 2px in.
///
/// A centre tap passes on every one of these controls today: the glyph or the
/// label sits at the centre, and it is the only render object accepting a hit.
/// It is the corners that were dead, so it is the corners this asserts.
///
/// [WidgetTester.tapAt] takes a raw offset, so it bypasses `warnIfMissed` and a
/// miss simply produces no callback — which is the failure being measured.
Future<void> tapEveryCorner(WidgetTester tester, Finder finder) async {
  final r = tester.getRect(finder);
  for (final p in <Offset>[
    r.topLeft + const Offset(2, 2),
    r.topRight + const Offset(-2, 2),
    r.bottomLeft + const Offset(2, -2),
    r.bottomRight + const Offset(-2, -2),
  ]) {
    await tester.tapAt(p);
    await tester.pump();
  }
}
