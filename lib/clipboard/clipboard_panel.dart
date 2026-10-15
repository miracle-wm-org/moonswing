// The clipboard history panel: a column docked against one edge of an output,
// listing everything copied, newest first. A click on an entry puts it back on
// the clipboard, ready to paste wherever the user's focus already is.
//
// The window is the root's (`_createClipboardWindow` in `main.dart`), and its
// shape is the feature:
//
// - **It never takes the keyboard.** Keyboard mode `none`, like a bar: the
//   point of a clipboard history is to paste into the window you are working
//   in, and a panel that took focus on every click would take it off that
//   window. So there is no Escape and no search field here; everything is a
//   click or the scroll wheel, both of which reach a surface without focus.
// - **It stays until asked to go.** Its own close button, or the bar button
//   again. The coordinator registration is non-dismissable, so neither a click
//   elsewhere nor another popup opening takes it down.
// - **It reserves its width.** An exclusive zone the width of the panel, so
//   the compositor moves windows out of its way rather than under it.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/clipboard_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup.dart';
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
    required this.closingNotifier,
    required this.onClosed,
    this.store,
    this.now,
  });

  /// The edge the window is docked against, which the panel slides in from.
  final ClipboardSide side;

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

class _ClipboardPanelState extends State<ClipboardPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  bool _leaving = false;

  ClipboardHistoryStore get _store =>
      widget.store ?? ClipboardHistoryStore.instance;

  @override
  void initState() {
    super.initState();
    // The panel's own lease, so the history keeps recording while it is open
    // even if the bar that opened it goes away (a monitor unplugged).
    _store.acquire();
    _controller = AnimationController(
      vsync: this,
      duration: ShellDurations.slow,
      // An exit is the user being done; it does not need the entrance's pace.
      reverseDuration: ShellDurations.base,
    );
    // Out of, and back into, the edge the panel is docked against: anything
    // moving the other way would open a strip between the panel and the screen
    // edge — the notification panel's rule.
    final away = widget.side == ClipboardSide.left ? -1.0 : 1.0;
    _slide = Tween<Offset>(begin: Offset(away, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _controller.forward();
    widget.closingNotifier.addListener(_onClosingRequested);
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingRequested);
    _controller.dispose();
    _store.release();
    super.dispose();
  }

  void _onClosingRequested() {
    if (!widget.closingNotifier.value || _leaving) return;
    _leaving = true;
    _controller.reverse().then((_) => widget.onClosed());
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = _store;
    // The inner edge, the one that faces the windows, gets the divider line;
    // the outer one is the screen edge and a line there would be drawn on
    // nothing.
    final inner = BorderSide(color: theme.divider);
    return PopupDismissArea(
      // A click in the panel is a click elsewhere as far as any bar popup is
      // concerned. The panel's own registration refuses dismissal, so it is
      // the one thing this leaves open.
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: ShellFontSizes.body,
          color: theme.popupForeground,
        ),
        child: ClipRect(
          child: SlideTransition(
            position: _slide,
            child: Container(
              // Opaque whatever the theme says — the notification panel's rule:
              // this is read over whatever window would otherwise show
              // through, and the reserved zone means there is never anything
              // under it worth seeing.
              decoration: BoxDecoration(
                color: theme.popupBackground.withValues(alpha: 1.0),
                border: widget.side == ClipboardSide.left
                    ? Border(right: inner)
                    : Border(left: inner),
              ),
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
                            icon: FontAwesomeIcons.xmark,
                            onTap: store.dismissCopyError,
                          ),
                        ),
                      ),
                    Expanded(child: _buildBody(theme, store)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeConfig theme, ClipboardHistoryStore store) {
    if (!store.loaded) {
      return const Center(child: LoadingIndicator(size: 22));
    }
    final entries = store.entries;
    if (entries.isEmpty) return _ClipboardEmpty(theme: theme);
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
    final theme = ThemeScope.of(context);
    final entries = store.entries;
    final pinned = entries.where((e) => e.pinned).length;
    final count = entries.length;
    final summary = count == 0
        ? 'Nothing copied yet'
        : [
            count == 1 ? '1 item' : '$count items',
            if (pinned > 0) '$pinned pinned',
          ].join(', ');
    final clearable = count > pinned;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clipboard',
                  style: TextStyle(
                    fontSize: ShellFontSizes.heading,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.popupForeground.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Only while there is something it would remove: pinned entries are
          // exactly the ones "Clear" keeps.
          if (clearable) ...[
            HoverRegion(
              onTap: store.clear,
              builder: (context, hovered) => Container(
                height: ShellSizes.iconButton + 4,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered ? theme.accent.withValues(alpha: 0.18) : null,
                  border: Border.all(
                    color: theme.accent.withValues(alpha: hovered ? 0.9 : 0.5),
                  ),
                  borderRadius: BorderRadius.circular(ShellRadii.control),
                ),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    color: theme.accentText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            box: ShellSizes.iconButton + 6,
            size: ShellFontSizes.title,
            color: theme.popupForeground,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// The empty state, which is also the panel's instructions.
class _ClipboardEmpty extends StatelessWidget {
  const _ClipboardEmpty({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.clipboard,
              size: 40,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing copied yet',
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Text, pictures and files you copy appear here. Click one to '
              'copy it again, then paste it wherever you like.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.4,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
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
          decoration: BoxDecoration(
            color: hovered
                ? theme.surfaceHover.atMostAlpha(0.14)
                : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.card),
            border: Border.all(
              color: current
                  ? theme.accent.withValues(alpha: 0.7)
                  : theme.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: ShellSizes.iconButton,
                child: Row(
                  children: [
                    FaIcon(
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
                      icon: FontAwesomeIcons.thumbtack,
                      size: ShellFontSizes.caption,
                      color: entry.pinned ? theme.accentText : muted,
                      onTap: () => store.togglePin(entry),
                    ),
                    SettingsIconButton(
                      icon: FontAwesomeIcons.trashCan,
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

  static FaIconData _kindIcon(ClipboardEntry entry) => switch (entry.kind) {
    ClipboardKind.text => FontAwesomeIcons.alignLeft,
    ClipboardKind.image => FontAwesomeIcons.image,
    ClipboardKind.files => FontAwesomeIcons.folderOpen,
    ClipboardKind.media =>
      entry.mime.toLowerCase().startsWith('video/')
          ? FontAwesomeIcons.film
          : FontAwesomeIcons.music,
    ClipboardKind.binary => FontAwesomeIcons.file,
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
              errorBuilder: (context, _, _) => FaIcon(
                FontAwesomeIcons.image,
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
      ClipboardFileKind.image => FontAwesomeIcons.fileImage,
      ClipboardFileKind.video => FontAwesomeIcons.fileVideo,
      ClipboardFileKind.audio => FontAwesomeIcons.fileAudio,
      ClipboardFileKind.document => FontAwesomeIcons.fileLines,
      ClipboardFileKind.folder => FontAwesomeIcons.folder,
      ClipboardFileKind.other => FontAwesomeIcons.file,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          if (icon) ...[
            SizedBox(
              width: 14,
              child: FaIcon(
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
