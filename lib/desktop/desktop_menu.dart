import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_actions.dart';
import 'package:graceful_shell/scopes.dart';

/// One row of a desktop context menu.
class DesktopMenuEntry {
  const DesktopMenuEntry({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final FaIconData? icon;

  /// A disabled row is shown greyed rather than hidden, so the menu's shape
  /// does not change between items and the user can see what is unavailable.
  final bool enabled;
}

/// The themed card both desktop context menus render into.
///
/// Shaped like `ContextMenuCard` in `modules/app_directory.dart` — same
/// popupBackground, divider border, 8px radius and IntrinsicWidth so the popup
/// sizes to content — but with room for a leading icon and a disabled state,
/// which "Open with…" needs.
class DesktopMenuCard extends StatelessWidget {
  const DesktopMenuCard({
    super.key,
    required this.entries,
    this.header,
    this.onBack,
  });

  final List<DesktopMenuEntry> entries;

  /// Shown as a non-interactive title row. Used by the "Open with…" page to
  /// say what is being opened.
  final String? header;

  /// When set, a back row is drawn above the entries.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          color: theme.popupForeground,
          fontFamily: theme.fontFamily,
          fontSize: 13,
        ),
        child: IntrinsicWidth(
          child: Container(
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.divider, width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBack != null)
                  _DesktopMenuRow(
                    entry: DesktopMenuEntry(
                      label: 'Back',
                      icon: FontAwesomeIcons.arrowLeft,
                      onTap: onBack!,
                    ),
                  ),
                if (header case final text?) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.muted,
                      ),
                    ),
                  ),
                  Container(height: 1, color: theme.divider),
                  const SizedBox(height: 4),
                ],
                for (final entry in entries)
                  _DesktopMenuRow(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMenuRow extends StatefulWidget {
  const _DesktopMenuRow({required this.entry});

  final DesktopMenuEntry entry;

  @override
  State<_DesktopMenuRow> createState() => _DesktopMenuRowState();
}

class _DesktopMenuRowState extends State<_DesktopMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final entry = widget.entry;
    final foreground =
        entry.enabled ? theme.popupForeground : theme.muted;

    return MouseRegion(
      cursor: entry.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (entry.enabled) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.enabled ? entry.onTap : null,
        child: Container(
          color: _hovered ? theme.surfaceHover : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.icon case final icon?) ...[
                SizedBox(
                  width: 16,
                  child: FaIcon(icon, size: 12, color: foreground),
                ),
                const SizedBox(width: 8),
              ],
              // Flexible so a long handler name ellipsizes against the popup's
              // maxWidth instead of overflowing the row. `overflow` alone does
              // nothing while the Text is unbounded inside a min-size Row.
              Flexible(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two-page desktop item menu.
///
/// "Open with…" is a **second page of the same popup**, not a child popup: a
/// nested popup is a separate Wayland surface and would inherit the
/// pointer-crossing problem `modules/app_directory.dart` documents, for no
/// benefit when the pages are mutually exclusive anyway.
class DesktopItemMenu extends StatefulWidget {
  const DesktopItemMenu({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onOpenWith,
    required this.onRename,
    required this.onRemove,
    required this.handlers,
  });

  final DesktopItem item;
  final VoidCallback onOpen;
  final void Function(AppEntry handler) onOpenWith;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  /// Resolved lazily by the host, which also owns and disposes the entries —
  /// they carry live `GAppInfo*`s.
  final List<AppEntry> Function() handlers;

  @override
  State<DesktopItemMenu> createState() => _DesktopItemMenuState();
}

class _DesktopItemMenuState extends State<DesktopItemMenu> {
  List<AppEntry>? _handlers;

  @override
  Widget build(BuildContext context) {
    final handlers = _handlers;
    if (handlers != null) {
      return DesktopMenuCard(
        header: 'Open ${labelForItem(widget.item)} with',
        onBack: () => setState(() => _handlers = null),
        entries: [
          if (handlers.isEmpty)
            DesktopMenuEntry(
              label: 'No applications available',
              enabled: false,
              onTap: () {},
            ),
          for (final handler in handlers)
            DesktopMenuEntry(
              label: handler.name,
              onTap: () => widget.onOpenWith(handler),
            ),
        ],
      );
    }

    // "Open with" is meaningless for an application, so the row is absent
    // rather than disabled — there is nothing for it to mean.
    final canOpenWith = widget.item.kind != DesktopItemKind.app;

    return DesktopMenuCard(
      entries: [
        DesktopMenuEntry(
          label: 'Open',
          icon: FontAwesomeIcons.arrowUpRightFromSquare,
          onTap: widget.onOpen,
        ),
        if (canOpenWith)
          DesktopMenuEntry(
            label: 'Open with…',
            icon: FontAwesomeIcons.listUl,
            onTap: () => setState(() => _handlers = widget.handlers()),
          ),
        DesktopMenuEntry(
          label: 'Rename',
          icon: FontAwesomeIcons.pen,
          onTap: widget.onRename,
        ),
        DesktopMenuEntry(
          label: 'Remove from desktop',
          icon: FontAwesomeIcons.trash,
          onTap: widget.onRemove,
        ),
      ],
    );
  }
}

/// The menu shown on right-clicking bare desktop.
class DesktopEmptyMenu extends StatelessWidget {
  const DesktopEmptyMenu({
    super.key,
    required this.onAddApplication,
    required this.onAddFile,
    required this.onOrganize,
    required this.onChangeBackground,
  });

  final VoidCallback onAddApplication;
  final VoidCallback onAddFile;
  final VoidCallback onOrganize;
  final VoidCallback onChangeBackground;

  @override
  Widget build(BuildContext context) {
    return DesktopMenuCard(
      entries: [
        DesktopMenuEntry(
          label: 'Add application…',
          icon: FontAwesomeIcons.rocket,
          onTap: onAddApplication,
        ),
        DesktopMenuEntry(
          label: 'Add file or folder…',
          icon: FontAwesomeIcons.folderOpen,
          onTap: onAddFile,
        ),
        DesktopMenuEntry(
          label: 'Organize',
          icon: FontAwesomeIcons.tableCells,
          onTap: onOrganize,
        ),
        DesktopMenuEntry(
          label: 'Change background…',
          icon: FontAwesomeIcons.image,
          onTap: onChangeBackground,
        ),
      ],
    );
  }
}
