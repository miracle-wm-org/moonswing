/// The three theme keys that shape a bar against the screen: how far it floats
/// off each side (`panel_margin`), how far each of its corners rounds
/// (`panel_radius`), and which of those corners round at all (`panel_corners`).
///
/// All three are read **in the bar's own frame**, so a name always means the
/// same part of a bar ([isVerticalAnchor]). A top or bottom bar's frame is the
/// screen's. A left or right bar's is a top bar turned a quarter turn
/// anticlockwise: its *right* end is at the top of the screen and its *left*
/// end at the bottom, its *top* side faces the screen's left edge and its
/// *bottom* side the screen's right. So `right` is always the far end of the
/// bar — a top bar's right-hand end, a side bar's top end — and `top_right` is
/// always the corner at that end on the bar's top side.
/// [PanelMargins.onScreen] and [PanelCorner.onScreen] turn the bar's frame
/// into the screen's, which is what a layer-shell margin and a
/// [BorderRadius] are given.
///
/// One consequence for a frame of several bars: two bars meet in a corner of
/// the screen only when *both* are flush there ([PanelMargins.flushAt]), and a
/// side bar's ends and outer edge read different keys from a top bar's.
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

/// Whether a bar anchored to [anchor] runs down a side of the screen, and so
/// reads its keys in the turned frame (see the library).
bool isVerticalAnchor(String anchor) => anchor == 'left' || anchor == 'right';

/// The screen edges a bar anchored to [anchor]'s two *ends* lie against: its
/// left and right ends on a top or bottom bar, its top and bottom ends on a
/// side one — in the bar's own start/end order (`PanelJoins`).
(String start, String end) panelEndEdges(String anchor) =>
    switch (screenEdgeOf(anchor)) {
      'left' || 'right' => ('top', 'bottom'),
      _ => ('left', 'right'),
    };

/// How far the bars float off each of their sides, in logical pixels, in the
/// bar's own frame (see the library).
///
/// A bar is given the margin of the side against its screen edge, which floats
/// it off that edge, and of its two ends, which stop them short of the screen's
/// sides; the side facing the middle of the screen has nothing to push against
/// and is not read. On a top or bottom bar the sides are the screen's. On a
/// side bar `right` is its top end, `left` its bottom end, and `top` and
/// `bottom` its long sides — `top` off the screen's left edge, `bottom` off its
/// right — so setting `right` moves the far end of every bar, whichever edge
/// it is on. [onScreen] is the same margins for one bar, as the screen reads
/// them.
///
/// Spelled in a theme file either as one number, every side alike — which is
/// what `panel_margin` always was, and what a uniform margin is still written
/// back as, and which means the same thing in either frame — or as a table of
/// the four sides, any one of them left out read as 0.
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
  ///
  /// In the frame these margins are in: a bar's own for the theme's value, the
  /// screen's for what [onScreen] answers.
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

  /// These margins, given in the bar's own frame, for a bar anchored to
  /// [anchor] as they lie on the screen: unchanged for a top or bottom bar,
  /// turned a quarter turn for a side one — its `right` is the screen's top,
  /// its `bottom` the screen's right, its `left` the screen's bottom and its
  /// `top` the screen's left.
  PanelMargins onScreen(String anchor) => isVerticalAnchor(anchor)
      ? PanelMargins(top: right, right: bottom, bottom: left, left: top)
      : this;

  /// Whether a top or bottom bar and a side bar would both be flush in the
  /// screen's [corner] — against both of that corner's screen edges — which
  /// is the only way two bars meet there.
  ///
  /// The two bars read the corner from different keys: a top bar in the
  /// top-left corner its `top` and `left`, a left bar there its `top` (its
  /// outer side) and `right` (its top end). So a corner is flush when three
  /// of the four margins are 0.
  bool flushAt(PanelCorner corner) {
    final (across, along) = corner.edges;
    final side = onScreen('left');
    return of(across) == 0 &&
        of(along) == 0 &&
        side.of(across) == 0 &&
        side.of(along) == 0;
  }

  /// Whether any corner of the screen is [flushAt] — whether two bars could
  /// meet anywhere at all under these margins.
  bool get anyFlushCorner => PanelCorner.values.any(flushAt);

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

/// One corner of a bar or of the screen.
///
/// Which, depends on who is asking: a theme names a corner in the bar's own
/// frame (`panel_radius`, `panel_corners`; see the library), while a
/// [BorderRadius], a join and [PanelCorner.of] are on the screen.
/// [onScreen] and [onBar] turn one into the other.
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

  /// The two edges that meet at this corner: the top or bottom one, then the
  /// left or right one.
  (String, String) get edges => switch (this) {
    topLeft => ('top', 'left'),
    topRight => ('top', 'right'),
    bottomRight => ('bottom', 'right'),
    bottomLeft => ('bottom', 'left'),
  };

  /// This corner, named in the frame of a bar anchored to [anchor], as it lies
  /// on the screen: itself on a top or bottom bar; on a side bar, turned a
  /// quarter turn anticlockwise — its top-right corner is the screen's
  /// top-left, at the bar's top end.
  PanelCorner onScreen(String anchor) => !isVerticalAnchor(anchor)
      ? this
      : switch (this) {
          topLeft => bottomLeft,
          topRight => topLeft,
          bottomRight => topRight,
          bottomLeft => bottomRight,
        };

  /// The inverse of [onScreen]: this screen corner of a bar anchored to
  /// [anchor], as the bar's own frame names it.
  PanelCorner onBar(String anchor) => !isVerticalAnchor(anchor)
      ? this
      : switch (this) {
          topLeft => topRight,
          topRight => bottomRight,
          bottomRight => bottomLeft,
          bottomLeft => topLeft,
        };

  /// The *screen* corner of a bar anchored to [anchor] that lies on its
  /// [outer] edge (against the screen edge it sits on) or its inner one
  /// (facing the middle of the screen), at its start or its end — the start is
  /// the left or top end, as `PanelJoins` reads them.
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
/// it floats — named in the bar's own frame (see the library), so
/// `["top_right", "bottom_right"]` rounds the far end of every bar: a top
/// bar's right-hand end and a side bar's top end. Either way, an inner corner where two bars meet under a
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

/// How far each of a bar's corners rounds, in logical pixels — `panel_radius`.
///
/// Named in the bar's own frame, as the margins are (see the library): on a
/// side bar `top_right` is the corner at its top end on the side facing the
/// screen's left edge. Which corners round at all is still `panel_corners`'s
/// ([PanelCornerChoice]); a corner it picks with a radius of 0 here is square.
///
/// Spelled in a theme file either as one number, every corner alike — which is
/// what `panel_radius` always was, and what a uniform set is still written back
/// as — or as a table of `top_left`, `top_right`, `bottom_right` and
/// `bottom_left`, any one of them left out read as 0.
@immutable
class PanelRadii {
  const PanelRadii({
    this.topLeft = 0,
    this.topRight = 0,
    this.bottomRight = 0,
    this.bottomLeft = 0,
  });

  /// Every corner alike: the radius a single number in a theme file means.
  const PanelRadii.all(double radius)
    : topLeft = radius,
      topRight = radius,
      bottomRight = radius,
      bottomLeft = radius;

  static const PanelRadii zero = PanelRadii();

  final double topLeft;
  final double topRight;
  final double bottomRight;
  final double bottomLeft;

  /// The radius at [corner], in the bar's own frame.
  double of(PanelCorner corner) => switch (corner) {
    PanelCorner.topLeft => topLeft,
    PanelCorner.topRight => topRight,
    PanelCorner.bottomRight => bottomRight,
    PanelCorner.bottomLeft => bottomLeft,
  };

  /// This with [corner]'s radius replaced by [radius].
  PanelRadii withCorner(PanelCorner corner, double radius) => PanelRadii(
    topLeft: corner == PanelCorner.topLeft ? radius : topLeft,
    topRight: corner == PanelCorner.topRight ? radius : topRight,
    bottomRight: corner == PanelCorner.bottomRight ? radius : bottomRight,
    bottomLeft: corner == PanelCorner.bottomLeft ? radius : bottomLeft,
  );

  /// Whether every corner has the same radius — which is how it is written
  /// back.
  bool get isUniform =>
      topLeft == topRight &&
      topRight == bottomRight &&
      bottomRight == bottomLeft;

  /// Whether no corner rounds at all.
  bool get isZero =>
      topLeft <= 0 && topRight <= 0 && bottomRight <= 0 && bottomLeft <= 0;

  /// The largest of the four: what a key that mirrors the bar's rounding as one
  /// number (a popup matching its bar) reads.
  double get largest => [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ].reduce((a, b) => a > b ? a : b);

  /// Reads a `panel_radius` value: a number for every corner, or a table of
  /// corners.
  ///
  /// Under the `TomlReader` discipline, one level down: a table whose
  /// `top_left` is a string costs `top_left`, which falls back to [fallback]'s,
  /// and keeps the other three. Every number is clamped into [min]..[max]; an
  /// absent corner in a table is 0. Null when [value] is neither shape, so the
  /// caller's fallback stands for the whole key.
  static PanelRadii? fromValue(
    Object? value, {
    PanelRadii fallback = PanelRadii.zero,
    double min = 0,
    double max = 64,
  }) {
    if (value is num) {
      if (!value.isFinite) return null;
      return PanelRadii.all(value.toDouble().clamp(min, max));
    }
    if (value is Map) {
      final map = <String, dynamic>{
        for (final MapEntry(:key, :value) in value.entries) '$key': value,
      };
      double corner(PanelCorner c) => map.containsKey(c.slug)
          ? map.doubleOr(c.slug, fallback.of(c), min: min, max: max)
          : 0;
      return PanelRadii(
        topLeft: corner(PanelCorner.topLeft),
        topRight: corner(PanelCorner.topRight),
        bottomRight: corner(PanelCorner.bottomRight),
        bottomLeft: corner(PanelCorner.bottomLeft),
      );
    }
    return null;
  }

  /// The value a theme file is given: the one number while every corner
  /// agrees, so a theme that never used the per-corner form is written exactly
  /// as it always was, and the table of all four otherwise.
  Object encode() => isUniform
      ? topLeft
      : <String, dynamic>{
          for (final corner in PanelCorner.values) corner.slug: of(corner),
        };

  @override
  bool operator ==(Object other) =>
      other is PanelRadii &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => isUniform
      ? 'PanelRadii.all($topLeft)'
      : 'PanelRadii(topLeft: $topLeft, topRight: $topRight, '
            'bottomRight: $bottomRight, bottomLeft: $bottomLeft)';
}
