import 'dart:async';

import 'package:flutter/widgets.dart';

/// Inserts a modal into the nearest **root** [Overlay] and resolves with whatever
/// the modal passes to `close`. Closing is idempotent — a modal whose backdrop
/// and Escape handler both fire completes once.
///
/// Root, not nearest: the settings content pane is a nested `Navigator`, and a
/// scrim inserted into *its* overlay would cover the pane's content while leaving
/// the sidebar and header live.
///
/// This is the in-window flavour; a surface that cannot host a modal at all (the
/// desktop, on the background layer) goes through a `RequestController` to the
/// root instead.
Future<T> showRootModal<T>(
  BuildContext context,
  Widget Function(void Function(T result) close) builder,
) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<T>();
  late OverlayEntry entry;

  void close(T result) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(builder: (_) => builder(close));
  overlay.insert(entry);
  return completer.future;
}
