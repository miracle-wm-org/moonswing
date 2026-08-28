import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A proxy that counts how many times it is asked to paint.
///
/// Put under a [RepaintBoundary] of its own, it answers the only question a
/// scroll- or hover-performance regression has: did anything *outside* the
/// thing the pointer touched have to be re-recorded? A render object marked
/// needing paint dirties everything up to the nearest repaint boundary, so a
/// widget with none of its own re-records this counter — and with it the whole
/// surrounding picture — on every pointer move, and the GTK embedder, which
/// implements no partial repaint, rasters the whole output again after it.
///
/// Shared between `calendar_tab_test.dart`, which wrote it, and
/// `settings_paint_test.dart`, which pins the same property one pane over.
class PaintCounter extends SingleChildRenderObjectWidget {
  const PaintCounter({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPaintCounter();
}

class RenderPaintCounter extends RenderProxyBox {
  int paints = 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    super.paint(context, offset);
  }
}
