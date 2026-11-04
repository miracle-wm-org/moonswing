/// The two theme keys that shape a bar against the screen: how far it floats off
/// each screen edge (`panel_margin`) and which of its corners round
/// (`panel_corners`).
///
/// Both are read **as the bar sits on the screen**, the way the
/// `panel_gradient_*` corners are: `top_left` is the top-left corner of every
/// bar, and `left` is the screen's left edge. That is what lets one theme
/// describe a frame of several bars. A margin on the screen's left edge is the
/// left bar's distance off it *and* the distance the top and bottom bars' left
/// ends stop short of it — the two are the same line, which is exactly the
/// condition for two bars to meet in that corner (`panel_join.dart`).
///
/// Flutter-free apart from `foundation`, so the pure arithmetic is testable on
/// its own.
library;

import 'package:flutter/foundation.dart';

import 'package:moonswing/config_reader.dart';

/// A screen edge, spelled as a panel's `anchor` is: `top`, `right`, `bottom`,
/// `left`. Anything else is read as `top`, which is what an unknown anchor gets
/// everywhere else.
String screenEdgeOf(String anchor) => switch (anchor) {
  'bottom' || 'left' || 'right' => anchor,
  _ => 'top',
};

/// The screen edges a bar anchored to [anchor]'s two *ends* lie against: its
/// left and right ends on a top or bottom bar, its top and bottom ends on a
/// side one — in the bar's own start/end order (`PanelJoins`).
(String start, String end) panelEndEdges(String anchor) =>
    switch (screenEdgeOf(anchor)) {
      'left' || 'right' => ('top', 'bottom'),
      _ => ('left', 'right'),
    };

/// How far the bars float off each screen edge, in logical pixels.
///
/// Each bar is handed the margin of every edge it is anchored to: its own
/// edge's ([of] its anchor) floats it off the screen edge it sits on, and the
/// two edges at its ends ([panelEndEdges]) stop its ends short of the screen's
/// sides. So `{ top = 0, left = 0, right = 8, bottom = 8 }` puts a top bar flush
/// against the top and left of the screen with its right end 8px short of the
/// right edge — flush where it meets a left bar, floating where it does not.
///
/// Spelled in a theme file either as one number, every edge alike — which is
/// what `panel_margin` always was, and what a uniform margin is still written
/// back as — or as a table of the four edges, any one of them left out read as
/// 0.
@immutable
class PanelMargins {
  const PanelMargins({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });

  /// Every edge alike: the margin a single number in a theme file means.
  const PanelMargins.all(int margin)
    : top = margin,
      right = margin,
      bottom = margin,
      left = margin;

  static const PanelMargins zero = PanelMargins();

  final int top;
  final int right;
  final int bottom;
  final int left;

  /// The margin on [edge], read as [screenEdgeOf] reads an anchor.
  int of(String edge) => switch (screenEdgeOf(edge)) {
    'right' => right,
    'bottom' => bottom,
    'left' => left,
    _ => top,
  };

  /// This with [edge]'s margin replaced by [margin].
  PanelMargins withEdge(String edge, int margin) => switch (screenEdgeOf(
    edge,
  )) {
    'right' => PanelMargins(
      top: top,
      right: margin,
      bottom: bottom,
      left: left,
    ),
    'bottom' => PanelMargins(
      top: top,
      right: right,
      bottom: margin,
      left: left,
    ),
    'left' => PanelMargins(
      top: top,
      right: right,
      bottom: bottom,
      left: margin,
    ),
    _ => PanelMargins(top: margin, right: right, bottom: bottom, left: left),
  };

  /// Whether every edge has the same margin — which is how it is written back.
  bool get isUniform => top == right && right == bottom && bottom == left;

  /// Whether no edge has any margin: every bar flush against the screen.
  bool get isZero => top == 0 && right == 0 && bottom == 0 && left == 0;

  /// Whether both screen edges that meet at [corner] are flush — the only
  /// corner two bars can meet in.
  bool flushAt(PanelCorner corner) => switch (corner) {
    PanelCorner.topLeft => top == 0 && left == 0,
    PanelCorner.topRight => top == 0 && right == 0,
    PanelCorner.bottomRight => bottom == 0 && right == 0,
    PanelCorner.bottomLeft => bottom == 0 && left == 0,
  };

  /// Whether any corner of the screen is [flushAt] — whether two bars could
  /// meet anywhere at all under these margins.
  bool get anyFlushCorner =>
      (top == 0 || bottom == 0) && (left == 0 || right == 0);

  static const List<String> edges = ['top', 'right', 'bottom', 'left'];

  /// Reads a `panel_margin` value: a number for every edge, or a table of edges.
  ///
  /// Under the `TomlReader` discipline, one level down: a table whose `left`
  /// is a string costs `left`, which falls back to [fallback]'s, and keeps the
  /// other three. Every number is clamped into [min]..[max]; an absent edge in
  /// a table is 0. Null when [value] is neither shape, so the caller's fallback
  /// stands for the whole key.
  static PanelMargins? fromValue(
    Object? value, {
    PanelMargins fallback = PanelMargins.zero,
    int min = 0,
    int max = 256,
  }) {
    int read(Map<String, dynamic> map, String key, int orElse) => map
        .doubleOr(
          key,
          orElse.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
        )
        .round();

    if (value is num) {
      if (!value.isFinite) return null;
      return PanelMargins.all(read({'v': value}, 'v', 0));
    }
    if (value is Map) {
      final map = <String, dynamic>{
        for (final MapEntry(:key, :value) in value.entries) '$key': value,
      };
      int edge(String key) =>
          map.containsKey(key) ? read(map, key, fallback.of(key)) : 0;
      return PanelMargins(
        top: edge('top'),
        right: edge('right'),
        bottom: edge('bottom'),
        left: edge('left'),
      );
    }
    return null;
  }

  /// The value a theme file is given: the one number while every edge agrees,
  /// so a theme that never used the per-edge form is written exactly as it
  /// always was, and the table of all four otherwise.
  Object encode() => isUniform
      ? top
      : <String, dynamic>{
          'top': top,
          'right': right,
          'bottom': bottom,
          'left': left,
        };

  @override
  bool operator ==(Object other) =>
      other is PanelMargins &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => isUniform
      ? 'PanelMargins.all($top)'
      : 'PanelMargins(top: $top, right: $right, bottom: $bottom, left: $left)';
}

/// One corner of a bar, as the bar sits on the screen.
enum PanelCorner {
  topLeft('top_left', 'Top left'),
  topRight('top_right', 'Top right'),
  bottomRight('bottom_right', 'Bottom right'),
  bottomLeft('bottom_left', 'Bottom left');

  const PanelCorner(this.slug, this.label);

  /// How a theme file spells it.
  final String slug;

  /// How the settings pane shows it.
  final String label;

  static PanelCorner? fromSlug(String? slug) {
    for (final corner in values) {
      if (corner.slug == slug) return corner;
    }
    return null;
  }

  /// The corner of a bar anchored to [anchor] that lies on its [outer] edge
  /// (against the screen edge it sits on) or its inner one (facing the middle
  /// of the screen), at its start or its end — the bar's own coordinates, as
  /// `PanelJoins` reads them.
  static PanelCorner of(
    String anchor, {
    required bool outer,
    required bool start,
  }) {
    switch (screenEdgeOf(anchor)) {
      case 'bottom':
        return outer
            ? (start ? bottomLeft : bottomRight)
            : (start ? topLeft : topRight);
      case 'left':
        return outer
            ? (start ? topLeft : bottomLeft)
            : (start ? topRight : bottomRight);
      case 'right':
        return outer
            ? (start ? topRight : bottomRight)
            : (start ? topLeft : bottomLeft);
      default: // 'top'
        return outer
            ? (start ? topLeft : topRight)
            : (start ? bottomLeft : bottomRight);
    }
  }
}

/// Which of a bar's corners `panel_radius` rounds.
///
/// [auto] is the rule the bar always had, now read edge by edge: the two
/// corners facing the middle of the screen always round, and a corner against
/// the screen edge rounds only where the bar is not flush in the display's own
/// corner — off the edge it sits on, or with its end stopped short of the
/// screen's side — since a rounded corner there would cut a wallpaper wedge out
/// of the display's corner. A uniform margin above zero therefore rounds all
/// four, and none rounds the inner two.
///
/// Otherwise the [corners] chosen round on every bar, wherever it is and however
/// it floats. Either way, an inner corner where two bars meet under a
/// `panel_join_radius` stays square, because the fillet is what turns it.
@immutable
class PanelCornerChoice {
  const PanelCornerChoice._(this._corners);

  /// The corners chosen, on every bar.
  const PanelCornerChoice.only(Set<PanelCorner> corners) : _corners = corners;

  /// The automatic rule; see the class.
  static const PanelCornerChoice auto = PanelCornerChoice._(null);

  /// Every corner.
  static const PanelCornerChoice all = PanelCornerChoice.only({
    PanelCorner.topLeft,
    PanelCorner.topRight,
    PanelCorner.bottomRight,
    PanelCorner.bottomLeft,
  });

  /// No corner: a square bar whatever `panel_radius` says.
  static const PanelCornerChoice none = PanelCornerChoice.only({});

  final Set<PanelCorner>? _corners;

  bool get isAuto => _corners == null;

  /// The corners chosen, or null for [auto].
  Set<PanelCorner>? get corners => _corners;

  /// Reads a `panel_corners` value: `"auto"`, `"all"`, `"none"`, or a list of
  /// corner names (`top_left`, `top_right`, `bottom_right`, `bottom_left`).
  ///
  /// An unknown name in the list costs that name, never the list. Null for any
  /// other value, so the caller's fallback stands for the whole key.
  static PanelCornerChoice? fromValue(Object? value) {
    if (value is String) {
      return switch (value.trim()) {
        'auto' => auto,
        'all' => all,
        'none' => none,
        final s => switch (PanelCorner.fromSlug(s)) {
          final PanelCorner corner => PanelCornerChoice.only({corner}),
          null => null,
        },
      };
    }
    if (value is List) {
      return PanelCornerChoice.only({
        for (final entry in value)
          if (entry is String) ?PanelCorner.fromSlug(entry.trim()),
      });
    }
    return null;
  }

  /// The value a theme file is given: a word for the three named choices, and
  /// the chosen corners clockwise from the top-left otherwise.
  Object encode() {
    final corners = _corners;
    if (corners == null) return 'auto';
    if (corners.isEmpty) return 'none';
    if (corners.length == PanelCorner.values.length) return 'all';
    return [
      for (final corner in PanelCorner.values)
        if (corners.contains(corner)) corner.slug,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is PanelCornerChoice &&
      (isAuto
          ? other.isAuto
          : !other.isAuto && setEquals(other._corners, _corners));

  @override
  int get hashCode => isAuto
      ? 0
      : Object.hashAllUnordered([for (final c in _corners!) c.index]);

  @override
  String toString() =>
      isAuto ? 'PanelCornerChoice.auto' : 'PanelCornerChoice($_corners)';
}
