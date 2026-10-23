import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:moonswing/theme/theme_config.dart';

/// Keeps a theme switch that moves the panels' reach (`panel_overhang`) from
/// resizing a bar's surface and restyling it in the same frame.
///
/// The engine draws a resized view from the last frame it has until a frame of
/// the new size arrives, and gives up waiting after 100ms. Drawn from a texture
/// shorter than the window, that last frame *tiles*, since a GL texture repeats
/// by default: switching Glassy for Forest grew a 32px bar's surface to 96px,
/// and the first Forest frame (its material, its foliage grown from nothing)
/// took longer than the wait, so for a moment there were three Glassy bars
/// stacked down the screen. So the two halves are never one frame:
///
/// - **Growing**, the surface grows first, under the theme the panels already
///   show — a frame that costs no more than the one before it, at the new size,
///   is what the engine waits for — and the panels are restyled only once every
///   one of them has laid out at the new depth.
/// - **Shrinking**, the panels are restyled first, at the size they have, and
///   the surface shrinks once that frame is out.
///
/// Either way the frame that changes a surface's size draws what the frame
/// before it drew. Every other change (a colour, a font) reaches [shown] at
/// once, so a colour-picker drag restyles the bars as live as everything else.
///
/// The probes and the frame wait are injected so the order is a plain widget
/// test (`test/panel_reach_test.dart`).
class PanelReachSequencer {
  PanelReachSequencer({
    required ThemeConfig initial,
    required this.target,
    required this.commit,
    required this.reached,
    Future<void> Function()? nextFrame,
    this.maxFrames = 30,
  }) : shown = ValueNotifier(initial),
       _committed = initial.panelReach,
       _nextFrame = nextFrame ?? _scheduleFrame;

  /// The theme the panels render — what their `ThemeProvider` listens to.
  final ValueNotifier<ThemeConfig> shown;

  /// The theme being switched to: the store's.
  final ThemeConfig Function() target;

  /// Commits a reach to every panel surface.
  final void Function(int reach) commit;

  /// Whether every panel's view has laid out at the depth last committed.
  final bool Function() reached;

  /// Frames to wait for the compositor to resize the surfaces before
  /// restyling anyway. A compositor that never configures the new size would
  /// otherwise leave the bars on the old theme for good, which is worse than
  /// the glitch this exists to prevent.
  final int maxFrames;

  final Future<void> Function() _nextFrame;

  /// The reach the panel surfaces were last given.
  int get committed => _committed;
  int _committed;

  bool _running = false;
  bool _dirty = false;
  bool _disposed = false;

  /// Moves the panels toward [target], in whichever order its reach needs.
  ///
  /// Called on every theme change; a call while a resize is under way is
  /// folded into it, and whatever the store holds once it lands is applied.
  void update() {
    if (_disposed) return;
    if (_running) {
      _dirty = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    try {
      do {
        _dirty = false;
        final theme = target();
        if (theme.panelReach > _committed) {
          _committed = theme.panelReach;
          commit(_committed);
          for (var frames = 0; frames < maxFrames; frames++) {
            await _nextFrame();
            if (_disposed) return;
            // Checked after the frame, so the frame the probe saw at the new
            // depth was laid out under the old theme; the restyle is the next.
            if (reached()) break;
          }
          // Round again for the restyle, against whatever the store holds now.
          _dirty = true;
          continue;
        }
        shown.value = theme;
        if (theme.panelReach < _committed) {
          await _nextFrame();
          if (_disposed) return;
          // No less than the store now wants either: a switch back during the
          // wait regrows the surface on the next round, and needs no shrink
          // first.
          final keep = target().panelReach;
          final reach = keep > theme.panelReach ? keep : theme.panelReach;
          if (reach < _committed) {
            _committed = reach;
            commit(_committed);
          }
        }
      } while (_dirty && !_disposed);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    shown.dispose();
  }
}

/// Requests a frame and completes once it has been laid out and painted.
///
/// `addPostFrameCallback` does not request a frame of its own, and a shell with
/// nothing animating produces none — `WindowTeardown`'s rule.
Future<void> _scheduleFrame() {
  final done = Completer<void>();
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) => done.complete());
  binding.scheduleFrame();
  return done.future;
}
