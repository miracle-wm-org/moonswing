// `[modules.clipboard]`, as a typed object.
//
// Beside the store rather than in `modules/clipboard.dart` because the bar
// button is not the only reader: the root reads the side, width and animation
// when it creates the panel's window, and the history store reads the rest.

import 'package:moonswing/config_reader.dart';
import 'package:moonswing/docked_panel.dart';

class ClipboardConfig {
  const ClipboardConfig({
    this.side = DockSide.left,
    this.width = 360,
    this.maxEntries = 100,
    this.persist = true,
    this.maxItemMb = 32,
    this.animation = const DockedPanelAnimation(),
  });

  /// The edge the panel is docked against. Left by default.
  final DockSide side;

  /// How wide the panel is, in logical pixels — and so how much of the output
  /// it takes from the windows beside it, since the panel reserves exactly its
  /// own width.
  final int width;

  /// How many entries the history keeps. Pinned entries are kept on top of
  /// this, never trimmed.
  final int maxEntries;

  /// Whether the history survives a restart. Off, it is wiped every time the
  /// shell starts, and nothing copied is left on disk afterwards.
  final bool persist;

  /// The largest single thing the history records, in megabytes. Anything
  /// bigger is left on the clipboard and simply not remembered — a copied
  /// video file is a path, not its contents, so this is about images and raw
  /// media data put on the clipboard directly.
  final int maxItemMb;

  /// The `animation*` keys: how the panel flies out of its edge and back.
  final DockedPanelAnimation animation;

  int get maxItemBytes => maxItemMb * 1024 * 1024;

  factory ClipboardConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClipboardConfig();
    return ClipboardConfig(
      side: DockSide.parse(map.stringOrNull('side')),
      width: map.intOr(
        'width',
        360,
        min: kDockedPanelMinWidth,
        max: kDockedPanelMaxWidth,
      ),
      maxEntries: map.intOr('max_entries', 100, min: 1, max: 1000),
      persist: map.boolOr('persist', true),
      maxItemMb: map.intOr('max_item_mb', 32, min: 1, max: 1024),
      animation: DockedPanelAnimation.fromMap(map),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardConfig &&
          other.side == side &&
          other.width == width &&
          other.maxEntries == maxEntries &&
          other.persist == persist &&
          other.maxItemMb == maxItemMb &&
          other.animation == animation;

  @override
  int get hashCode =>
      Object.hash(side, width, maxEntries, persist, maxItemMb, animation);
}
