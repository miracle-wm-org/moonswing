// What the shell's own screenshot and recording features capture.
//
// Deliberately Flutter-free, the rule `screencast/pick_types.dart` states for its
// half of this — which is what keeps the geometry a plain unit test.
//
// One coordinate rule runs through the whole file. Everything the user selects is
// in the compositor's **logical** pixels, because that is what miracle's IPC
// reports and what a layer-shell surface is laid out in; a captured buffer is in
// **physical** pixels. The two differ by the output's scale, fractional scales
// included, so a [CaptureRect] is always logical and always carries the logical
// [CaptureSize] it was measured against — [CaptureRect.scaledInto] is the one
// place the conversion happens, and it derives the factor from the buffer it is
// handed rather than from any advertised scale.

/// A size in logical pixels.
class CaptureSize {
  const CaptureSize(this.width, this.height);

  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is CaptureSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// A point in logical pixels — used for one output's top-left corner in the
/// compositor's global space.
class CapturePoint {
  const CapturePoint(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is CapturePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CapturePoint($x, $y)';
}

/// A rectangle in logical pixels, either global (miracle's own space) or
/// relative to one output's top-left corner. Which one is always named by the
/// field holding it.
class CaptureRect {
  const CaptureRect(this.x, this.y, this.width, this.height);

  /// The rectangle spanned by two corners, in either order — a drag that ends up
  /// and to the left is the same selection as one that ends down and to the right.
  ///
  /// Spelled with ternaries in the initialiser list rather than as a factory so it
  /// stays `const`: a geometry type that cannot appear in a constant is one every
  /// test has to build at run time.
  const CaptureRect.fromCorners(int x0, int y0, int x1, int y1)
      : x = x0 < x1 ? x0 : x1,
        y = y0 < y1 ? y0 : y1,
        width = x1 > x0 ? x1 - x0 : x0 - x1,
        height = y1 > y0 ? y1 - y0 : y0 - y1;

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;

  bool get isEmpty => width <= 0 || height <= 0;

  CaptureSize get size => CaptureSize(width, height);

  bool contains(int pointX, int pointY) =>
      pointX >= x && pointX < right && pointY >= y && pointY < bottom;

  CaptureRect translate(int dx, int dy) =>
      CaptureRect(x + dx, y + dy, width, height);

  /// The overlap with [other], or an empty rect when they do not meet.
  CaptureRect intersect(CaptureRect other) {
    final left = x > other.x ? x : other.x;
    final top = y > other.y ? y : other.y;
    final r = right < other.right ? right : other.right;
    final b = bottom < other.bottom ? bottom : other.bottom;
    if (r <= left || b <= top) return const CaptureRect(0, 0, 0, 0);
    return CaptureRect(left, top, r - left, b - top);
  }

  /// This rectangle mapped from [logical] space into a capture buffer of
  /// [bufferWidth] x [bufferHeight], clipped to the buffer.
  ///
  /// The factor comes from the buffer the compositor actually produced rather than
  /// from the output's advertised `scale`: a fractional-scaled output reports 1.5
  /// and hands back a buffer at whatever rounding it settled on, and a crop off by
  /// that shows a sliver of the wrong window down one edge. Null when either space
  /// is degenerate — there is no honest mapping, and the caller keeps the frame.
  CaptureRect? scaledInto(
    CaptureSize logical,
    int bufferWidth,
    int bufferHeight,
  ) {
    if (logical.isEmpty || bufferWidth <= 0 || bufferHeight <= 0) return null;
    final sx = bufferWidth / logical.width;
    final sy = bufferHeight / logical.height;
    final left = (x * sx).round();
    final top = (y * sy).round();
    final scaled = CaptureRect(
      left,
      top,
      (right * sx).round() - left,
      (bottom * sy).round() - top,
    );
    final clipped = scaled.intersect(CaptureRect(0, 0, bufferWidth, bufferHeight));
    return clipped.isEmpty ? null : clipped;
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CaptureRect($x, $y, ${width}x$height)';
}

/// What a capture is of: one whole output, one window, or a rectangle the user
/// dragged out.
///
/// Every variant names a [connector] — a `wl_output.name`, the string miracle's
/// `OutputNode.name` and GDK's connector both carry — because even a window
/// capture needs a fallback source when the compositor cannot hand us a
/// foreign-toplevel handle, and that fallback is its output cropped to [crop].
///
/// The name is the identity and [outputOrigin] is the second pass behind it, for
/// `resolveOutput`'s reason: a connector is only an identity while *both* sides
/// have one. GDK reports none without an `xdg-output` manager and
/// `wl_output.name` does not exist below version 4, and matching two empty
/// strings resolves to nothing at all.
sealed class CaptureTarget {
  const CaptureTarget();

  /// The output this is captured from.
  String get connector;

  /// The output's logical size, which [crop] is expressed against.
  CaptureSize get outputSize;

  /// This output's top-left corner in the compositor's global logical space, or
  /// null when the shell could not learn it.
  ///
  /// Carried so [connector] is not the *only* way back to the display: two
  /// monitors cannot share a corner, so a position is an identity wherever a name
  /// is missing at either end. Nothing else reads it — a crop is output-local.
  CapturePoint? get outputOrigin => null;

  /// The region of the output to keep, in that output's *local* logical
  /// pixels, or null for all of it.
  CaptureRect? get crop;

  /// The `ext_foreign_toplevel_handle_v1.identifier` to capture directly, when
  /// there is one. Preferred over [crop] wherever it is set: a toplevel
  /// capture follows the window as it moves and resizes, and shows it whole
  /// even when something is stacked on top of it.
  String? get toplevelIdentifier => null;

  /// One line for a notification body or the recorder's readout.
  String get label;
}

/// A whole output.
class OutputCapture extends CaptureTarget {
  const OutputCapture({
    required this.connector,
    required this.outputSize,
    this.outputOrigin,
  });

  @override
  final String connector;

  @override
  final CaptureSize outputSize;

  @override
  final CapturePoint? outputOrigin;

  @override
  CaptureRect? get crop => null;

  /// The connector, or a word for it: a screen the compositor never named
  /// would otherwise put an empty string in a notification.
  @override
  String get label => connector.isNotEmpty ? connector : 'Screen';
}

/// One window.
///
/// [toplevelIdentifier] is null on a compositor without
/// `ext-foreign-toplevel-list`, and on a window the match could not resolve
/// unambiguously. Either way [crop] answers, at the cost of a rectangle that does
/// not follow the window.
class WindowCapture extends CaptureTarget {
  const WindowCapture({
    required this.connector,
    required this.outputSize,
    required this.crop,
    required this.title,
    required this.appId,
    this.outputOrigin,
    this.toplevelIdentifier,
  });

  @override
  final String connector;

  @override
  final CaptureSize outputSize;

  @override
  final CapturePoint? outputOrigin;

  @override
  final CaptureRect crop;

  @override
  final String? toplevelIdentifier;

  final String title;
  final String appId;

  /// Whether this capture follows the window rather than a fixed rectangle.
  bool get followsWindow => toplevelIdentifier != null;

  /// This capture with [identifier] as its foreign-toplevel handle.
  ///
  /// The selection surface cannot fill it in — it is a widget, and the
  /// toplevel list is on the capture connection's side of the FFI — so the
  /// pick carries the rectangle and the identifier is joined on afterwards.
  WindowCapture withToplevelIdentifier(String? identifier) => WindowCapture(
        connector: connector,
        outputSize: outputSize,
        crop: crop,
        title: title,
        appId: appId,
        outputOrigin: outputOrigin,
        toplevelIdentifier: identifier,
      );

  @override
  String get label => title.isNotEmpty ? title : (appId.isNotEmpty ? appId : 'Window');
}

/// A rectangle the user dragged out on one output.
class AreaCapture extends CaptureTarget {
  const AreaCapture({
    required this.connector,
    required this.outputSize,
    required this.crop,
    this.outputOrigin,
  });

  @override
  final String connector;

  @override
  final CaptureSize outputSize;

  @override
  final CapturePoint? outputOrigin;

  @override
  final CaptureRect crop;

  @override
  String get label => '${crop.width} x ${crop.height}';
}
