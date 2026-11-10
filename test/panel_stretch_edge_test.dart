import 'package:flutter_test/flutter_test.dart';
import 'package:layer_shell/layer_shell.dart';

import 'package:moonswing/popup.dart';

/// [setPanelMargin] lets go of [panelStretchEdge] and takes it again, so that
/// gtk-layer-shell sends a fresh `set_size(0)` along the bar and Mir forgets
/// the shorter length a margin left it at. That only works for an edge the bar
/// is stretched between: one of its two ends, whose opposite is anchored too.
/// Released at the bar's own screen edge instead, the toggle would send a
/// `set_size` across the bar — which changes nothing — and a margin that shrank
/// would still leave the bar short.
void main() {
  const opposite = {
    LayerShellEdge.top: LayerShellEdge.bottom,
    LayerShellEdge.bottom: LayerShellEdge.top,
    LayerShellEdge.left: LayerShellEdge.right,
    LayerShellEdge.right: LayerShellEdge.left,
  };

  for (final anchor in ['top', 'bottom', 'left', 'right']) {
    test('a $anchor bar re-stretches along its length', () {
      final edges = anchorEdgesForPosition(anchor);
      final end = panelStretchEdge(anchor);
      expect(edges, contains(end));
      expect(edges, contains(opposite[end]));
      expect(end.name, isNot(anchor),
          reason: 'the bar\'s own edge is not one it is stretched between');
    });
  }
}
