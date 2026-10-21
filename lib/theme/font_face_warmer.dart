import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lays a font family out once, between frames, before anything draws in it.
///
/// The font picker draws every row in its own face, and the first layout of a
/// family is where the engine pays for it: a fontconfig match, the file opened
/// and parsed, and — for a symbol, icon or CJK face that lacks the Latin
/// letters of its own name — a fallback search per missing glyph. All of that
/// runs on the UI thread *inside* the frame's layout, so a scroll that brought
/// fifteen unseen families into view paid for fifteen in one frame, and the
/// list stuttered on every flick through a few hundred of them.
///
/// So a row asks here first. A family already laid out in this process is
/// [isWarm] — the engine keeps the typeface — and draws in its face at once;
/// any other draws in the theme's font and is [request]ed. After each frame
/// the oldest requests are laid out with a throwaway [TextPainter] until
/// [budget] is spent (always at least one, so a slow face still progresses),
/// and their rows are told to switch. A row scrolled away before its turn
/// [cancel]s, so a fast scroll pays only for what it stopped on.
///
/// Post-frame callbacks rather than `scheduleTask`: those are timers, and a
/// queued one outlives a closed list in every widget test that opens it.
class FontFaceWarmer {
  FontFaceWarmer({
    this.budget = const Duration(milliseconds: 4),
    void Function(TextSpan span, TextScaler scaler)? layout,
  }) : _layout = layout ?? _layOut;

  static final FontFaceWarmer instance = FontFaceWarmer();

  /// How much of the gap after a frame one round of warming may spend.
  final Duration budget;

  final void Function(TextSpan span, TextScaler scaler) _layout;

  final _warm = <String>{};

  /// Waiting families, oldest first, each with what to lay out and who to tell.
  final _waiting = <String, _Request>{};

  bool _scheduled = false;

  bool isWarm(String family) => _warm.contains(family);

  /// Lays [family] out in [style] (which names it) at [scaler] after this
  /// frame, then calls [onWarm]. A family already warm calls nothing — check
  /// [isWarm] first.
  void request(
    String family,
    TextStyle style,
    TextScaler scaler,
    VoidCallback onWarm,
  ) {
    if (_warm.contains(family)) return;
    (_waiting[family] ??= _Request(
      TextSpan(text: family, style: style),
      scaler,
    )).listeners.add(onWarm);
    if (_scheduled) return;
    _scheduled = true;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => _run());
    binding.ensureVisualUpdate();
  }

  /// Withdraws [onWarm]; the family is dropped from the queue with its last
  /// listener.
  void cancel(String family, VoidCallback onWarm) {
    final request = _waiting[family];
    if (request == null) return;
    request.listeners.remove(onWarm);
    if (request.listeners.isEmpty) _waiting.remove(family);
  }

  void _run() {
    _scheduled = false;
    final clock = Stopwatch()..start();
    final done = <_Request>[];
    while (_waiting.isNotEmpty) {
      final family = _waiting.keys.first;
      final request = _waiting.remove(family)!;
      _layout(request.span, request.scaler);
      _warm.add(family);
      done.add(request);
      if (clock.elapsed >= budget) break;
    }
    // Told after the loop, so a listener that requests again lands in the
    // next round rather than this one.
    for (final request in done) {
      for (final listener in List.of(request.listeners)) {
        listener();
      }
    }
    if (_waiting.isNotEmpty && !_scheduled) {
      _scheduled = true;
      final binding = SchedulerBinding.instance;
      binding.addPostFrameCallback((_) => _run());
      binding.scheduleFrame();
    }
  }

  static void _layOut(TextSpan span, TextScaler scaler) {
    TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )
      ..layout()
      ..dispose();
  }
}

class _Request {
  _Request(this.span, this.scaler);

  final TextSpan span;
  final TextScaler scaler;
  final listeners = <VoidCallback>[];
}
