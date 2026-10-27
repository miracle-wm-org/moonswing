// The clipboard history panel: a column docked against one edge of an output,
// listing everything copied, newest first. A click on an entry puts it back on
// the clipboard, ready to paste wherever the user's focus already is.
//
// A docked panel (`lib/docked_panel.dart`), whose shape is the feature: it
// never takes the keyboard, so pasting goes into the window the user is
// already in; it stays until its own close button or the bar button takes it
// down; and it floats over the windows, so opening it moves none of them.

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/clipboard_store.dart';
import 'package:moonswing/docked_panel.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// Every card's height, gap included. Fixed, so the list is a fixed-extent
/// `ListView` however long the history grows.
const double kClipboardCardExtent = 112;

/// The gap under each card, inside [kClipboardCardExtent].
const double _cardGap = 8;

class ClipboardPanel extends StatefulWidget {
  const ClipboardPanel({
    super.key,
    required this.side,
    this.animation = const DockedPanelAnimation(),
    this.shadowReach = 0,
    required this.closingNotifier,
    required this.onClosed,
    this.store,
    this.now,
  });

  /// The edge the window is docked against, which the panel arrives from.
  final DockSide side;

  /// How it arrives and leaves, `[modules.clipboard] animation*`.
  final DockedPanelAnimation animation;

  /// The window's strip for the panel's shadow — [DockedPanel.shadowReach].
  final int shadowReach;

  /// Flipped by whoever wants the panel gone — its close button or the bar
  /// button. Starts the exit; [onClosed] tears the window down after it.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Defaults to the singleton; a widget test passes its own.
  final ClipboardHistoryStore? store;

  /// The clock the copy times are written against. For tests.
  final DateTime Function()? now;

  @override
  State<ClipboardPanel> createState() => _ClipboardPanelState();
}

class _ClipboardPanelState extends State<ClipboardPanel> {
  ClipboardHistoryStore get _store =>
      widget.store ?? ClipboardHistoryStore.instance;

  @override
  void initState() {
    super.initState();
    // The panel's own lease, so the history keeps recording while it is open
    // even if the bar that opened it goes away (a monitor unplugged).
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = _store;
    return DockedPanel(
      side: widget.side,
      animation: widget.animation,
      shadowReach: widget.shadowReach,
      closingNotifier: widget.closingNotifier,
      onClosed: widget.onClosed,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ClipboardHeader(
              store: store,
              onClose: () => widget.closingNotifier.value = true,
            ),
            Container(height: 1, color: theme.divider),
            if (store.error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: SettingsBanner(
                  title: store.unsupported
                      ? 'Not recording what you copy'
                      : 'Clipboard history stopped',
                  message: error,
                  action: SettingsActionButton(
                    label: 'Retry',
                    compact: true,
                    onTap: store.retry,
                  ),
                ),
              ),
            if (store.copyError case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: SettingsBanner(
                  title: 'Could not copy',
                  message: error,
                  action: SettingsIconButton(
                    icon: ShellGlyph.close,
                    onTap: store.dismissCopyError,
                  ),
                ),
              ),
            Expanded(child: _buildBody(store)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ClipboardHistoryStore store) {
    if (!store.loaded) {
      return const Center(child: LoadingIndicator(size: 22));
    }
    final entries = store.entries;
    if (entries.isEmpty) {
      return const DockedPanelEmpty(
        icon: ShellGlyph.clipboard,
        title: 'Nothing copied yet',
        message:
            'Text, pictures and files you copy appear here. Click one to '
            'copy it again, then paste it wherever you like.',
      );
    }
    final now = (widget.now ?? DateTime.now)();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemExtent: kClipboardCardExtent,
      // A screen and a half of cards either side: enough that a flick of the
      // wheel never shows a card still decoding, few enough that a long
      // history is not all laid out at once.
      scrollCacheExtent: const ScrollCacheExtent.pixels(
        kClipboardCardExtent * 4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Padding(
          key: ValueKey(entry.id),
          padding: const EdgeInsets.only(bottom: _cardGap),
          child: ClipboardCard(
            entry: entry,
            store: store,
            current: index == 0,
            now: now,
          ),
        );
      },
    );
  }
}

/// The title, the count, and the two ways to act on the whole panel.
class _ClipboardHeader extends StatelessWidget {
  const _ClipboardHeader({required this.store, required this.onClose});

  final ClipboardHistoryStore store;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final entries = store.entries;
    final pinned = entries.where((e) => e.pinned).length;
    final count = entries.length;
    final summary = count == 0
        ? 'Nothing copied yet'
        : [
            count == 1 ? '1 item' : '$count items',
            if (pinned > 0) '$pinned pinned',
          ].join(', ');
    return DockedPanelHeader(
      title: 'Clipboard',
      summary: summary,
      onClose: onClose,
      actions: [
        // Only while there is something it would remove: pinned entries are
        // exactly the ones "Clear" keeps.
        if (count > pinned)
          DockedPanelTextButton(label: 'Clear', onTap: store.clear),
      ],
    );
  }
}

/// One entry. A click anywhere on it but its two buttons copies it.
class ClipboardCard extends StatelessWidget {
  const ClipboardCard({
    super.key,
    required this.entry,
    required this.store,
    required this.current,
    required this.now,
  });

  final ClipboardEntry entry;
  final ClipboardHistoryStore store;

  /// Whether this is the newest entry — what is on the clipboard now, unless
  /// something has since cleared it.
  final bool current;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final meta = [
      describeClipboardEntry(entry),
      if (entry.kind.storesFile) formatClipboardSize(entry.size),
      formatCopiedAt(entry.copiedAt, now),
    ].join(' · ');
    final muted = theme.popupForeground.withValues(alpha: 0.6);
    // Its own boundary: a hover tints one card, and without this the whole
    // panel — every thumbnail in it — would be re-recorded for it.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: () => store.copy(entry),
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
          decoration: dockedPanelCardDecoration(
            context,
            hovered: hovered,
            ring: current ? theme.accent.withValues(alpha: 0.7) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: ShellSizes.iconButton,
                child: Row(
                  children: [
                    ShellIcon(
                      _kindIcon(entry),
                      size: ShellFontSizes.secondary,
                      color: muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.caption,
                          color: muted,
                        ),
                      ),
                    ),
                    _CopiedMark(store: store, id: entry.id),
                    SettingsIconButton(
                      icon: ShellGlyph.pin,
                      size: ShellFontSizes.caption,
                      color: entry.pinned ? theme.accentText : muted,
                      onTap: () => store.togglePin(entry),
                    ),
                    SettingsIconButton(
                      icon: ShellGlyph.trashCan,
                      size: ShellFontSizes.caption,
                      color: muted,
                      onTap: () => store.remove(entry),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _ClipboardContent(entry: entry, store: store),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static ShellGlyph _kindIcon(ClipboardEntry entry) => switch (entry.kind) {
    ClipboardKind.text => ShellGlyph.alignLeft,
    ClipboardKind.image => ShellGlyph.image,
    ClipboardKind.files => ShellGlyph.folderOpen,
    ClipboardKind.media =>
      entry.mime.toLowerCase().startsWith('video/')
          ? ShellGlyph.film
          : ShellGlyph.music,
    ClipboardKind.binary => ShellGlyph.file,
  };
}

/// "Copied", on the entry just put back, for a moment.
class _CopiedMark extends StatelessWidget {
  const _CopiedMark({required this.store, required this.id});

  final ClipboardHistoryStore store;
  final String id;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: store.justCopied,
      builder: (context, copied, _) => copied != id
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 6, right: 2),
              child: Text(
                'Copied',
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontWeight: FontWeight.w600,
                  color: theme.accentText,
                ),
              ),
            ),
    );
  }
}

/// What the card shows of its entry.
class _ClipboardContent extends StatelessWidget {
  const _ClipboardContent({required this.entry, required this.store});

  final ClipboardEntry entry;
  final ClipboardHistoryStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final muted = theme.popupForeground.withValues(alpha: 0.6);
    switch (entry.kind) {
      case ClipboardKind.text:
        return Text(
          clipboardTextPreview(entry.text ?? ''),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            height: 1.3,
            color: theme.popupForeground,
          ),
        );
      case ClipboardKind.image:
        return _Thumbnail(path: store.payloadPath(entry)!);
      case ClipboardKind.files:
        return _FileList(paths: entry.paths);
      case ClipboardKind.media:
      case ClipboardKind.binary:
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            entry.mime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: ShellFontSizes.secondary, color: muted),
          ),
        );
    }
  }
}

/// A picture, scaled down to the card. Decoded at the size it is drawn, not the
/// size it was copied at: a 4K screenshot decoded whole is 33MB of memory per
/// card.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 64.0;
        return Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ShellRadii.control),
            child: Image.file(
              File(path),
              height: height,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              cacheHeight: (height * dpr).round(),
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (context, _, _) => ShellIcon(
                ShellGlyph.image,
                size: 28,
                color: theme.popupForeground.withValues(alpha: 0.3),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The files of a copied-files entry: the first two by name, and a count of
/// the rest. A single picture is drawn as itself.
class _FileList extends StatelessWidget {
  const _FileList({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (paths.length == 1 &&
        fileKindForPath(paths.single) == ClipboardFileKind.image) {
      return Row(
        children: [
          // Capped, or a panorama would squeeze its own name off the card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: _Thumbnail(path: paths.single),
          ),
          const SizedBox(width: 10),
          Expanded(child: _fileRow(theme, paths.single, icon: false)),
        ],
      );
    }
    final shown = paths.take(2).toList();
    final rest = paths.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final path in shown) _fileRow(theme, path),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 20),
            child: Text(
              rest == 1 ? '1 more' : '$rest more',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fileRow(ThemeConfig theme, String path, {bool icon = true}) {
    final glyph = switch (fileKindForPath(path)) {
      ClipboardFileKind.image => ShellGlyph.fileImage,
      ClipboardFileKind.video => ShellGlyph.fileVideo,
      ClipboardFileKind.audio => ShellGlyph.fileAudio,
      ClipboardFileKind.document => ShellGlyph.fileText,
      ClipboardFileKind.folder => ShellGlyph.folder,
      ClipboardFileKind.other => ShellGlyph.file,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          if (icon) ...[
            SizedBox(
              width: 14,
              child: ShellIcon(
                glyph,
                size: ShellFontSizes.secondary,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              fileBaseName(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                color: theme.popupForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
