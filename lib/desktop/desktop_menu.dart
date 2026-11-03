import 'package:flutter/widgets.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_actions.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// One item of a context menu: a tappable [DesktopMenuEntry], or the
/// [DesktopMenuDivider], [DesktopMenuHeading] and [DesktopMenuLive] that group
/// and refresh them.
sealed class DesktopMenuItem {
  const DesktopMenuItem();
}

/// A rule between two groups of rows — a menu's own actions and the links to
/// its settings, say.
class DesktopMenuDivider extends DesktopMenuItem {
  const DesktopMenuDivider();
}

/// A small non-interactive label over the rows after it: the name of a choice
/// whose options follow as checkable rows.
class DesktopMenuHeading extends DesktopMenuItem {
  const DesktopMenuHeading(this.text);

  final String text;
}

/// Rows rebuilt whenever [listenable] notifies, for a menu that stays open
/// while what it shows moves — a quick setting the user just flipped, or one
/// flipped from somewhere else while the menu was up.
///
/// The popup's window is sized once, at open, so [build] must answer rows of
/// the same shape every time: a switch flips, a check moves, nothing comes or
/// goes.
class DesktopMenuLive extends DesktopMenuItem {
  const DesktopMenuLive({required this.listenable, required this.build});

  final Listenable listenable;
  final List<DesktopMenuItem> Function() build;
}

/// One row of a desktop context menu.
class DesktopMenuEntry extends DesktopMenuItem {
  const DesktopMenuEntry({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.selected = false,
    this.selectable = false,
    this.checked,
    this.iconColor,
  });

  final String label;
  final VoidCallback onTap;
  final ShellGlyph? icon;

  /// Draws [icon] in this colour rather than the row's, for a row whose icon
  /// *is* what it chooses — a sticky note's paper.
  final Color? iconColor;

  /// A disabled row is shown greyed rather than hidden, so the menu's shape
  /// does not change between items and the user can see what is unavailable.
  final bool enabled;

  /// Whether this row is the state the menu's subject is *already* in — one of
  /// a set of alternatives, drawn in the accent's reading colour
  /// (`ThemeConfig.accentText`) with a check after it.
  ///
  /// Marked rather than disabled, and rather than absent: a menu is read before
  /// it is clicked, so a set of choices has to say which one is current, and the
  /// current one going grey or vanishing would make the set change shape as the
  /// user moved through it. It stays tappable for the same reason — re-choosing
  /// what is already chosen is a no-op, not an error.
  final bool selected;

  /// Whether the row is one of a set whose [selected] member can move while
  /// the menu is open. Such a row keeps room for the check whether or not it
  /// carries one: the popup's surface is sized once, at open, so a check that
  /// moved onto the widest row would otherwise be cut off at the card's edge.
  final bool selectable;

  /// Non-null draws a small switch at the row's end, on or off — a boolean the
  /// row flips. The switch is the same width either way, so it can flip under
  /// an open menu.
  final bool? checked;
}

/// The themed card both desktop context menus render into.
///
/// The surface is shared with `ContextMenuCard` in `modules/app_directory.dart` —
/// both render into a [PopupCard], so the theme's popup shape reaches them from
/// one place — as is the IntrinsicWidth that lets the popup size to content. Only
/// the rows differ: this one has room for a leading icon and a disabled state.
class DesktopMenuCard extends StatelessWidget {
  const DesktopMenuCard({
    super.key,
    required this.entries,
    this.header,
    this.onBack,
  });

  final List<DesktopMenuItem> entries;

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
          child: PopupCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBack != null)
                  _DesktopMenuRow(
                    entry: DesktopMenuEntry(
                      label: 'Back',
                      icon: ShellGlyph.arrowLeft,
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
                for (final item in entries) _DesktopMenuItemView(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMenuItemView extends StatelessWidget {
  const _DesktopMenuItemView({required this.item});

  final DesktopMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return switch (item) {
      final DesktopMenuEntry entry => _DesktopMenuRow(entry: entry),
      DesktopMenuDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(height: 1, color: theme.divider),
      ),
      DesktopMenuHeading(:final text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
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
      DesktopMenuLive(:final listenable, :final build) => ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in build()) _DesktopMenuItemView(item: child),
          ],
        ),
      ),
    };
  }
}

/// The switch a [DesktopMenuEntry.checked] row ends in — [SettingsToggle]'s
/// track and thumb at a menu row's size, drawn rather than tappable: the whole
/// row is the target.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final track = on ? theme.accent : theme.divider;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: 26,
        height: 14,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(7),
        ),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: kOnAccent,
            shape: BoxShape.circle,
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
    // `accentText` rather than the accent: a checked row is a *label*, and the
    // accent is the colour this palette fills buttons with. The shell's own
    // theme put it on this card at 1.8:1, which made the one row the menu is
    // trying to point at the one row that could not be read.
    //
    // Under the pointer it gives way to the ordinary foreground, because the
    // fill it would then be read against is `surface_hover` — which in that
    // same theme *is* the accent, and no lift clears its own source colour.
    // The check after the label is what says "current" in either state, which
    // is the job it was put there for.
    final foreground = !entry.enabled
        ? theme.muted
        : entry.selected && !_hovered
            ? theme.accentText
            : theme.popupForeground;

    return MouseRegion(
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
                  child: ShellIcon(
                    icon,
                    size: 12,
                    color: entry.enabled
                        ? (entry.iconColor ?? foreground)
                        : foreground,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Flexible so a long handler name ellipsizes against the popup's
              // maxWidth instead of overflowing the row. `overflow` alone does
              // nothing while the Text is unbounded inside a min-size Row.
              // Tight on a switch row, so the switch lines up at the card's
              // end with every other switch rather than trailing its label.
              Flexible(
                fit: entry.checked == null ? FlexFit.loose : FlexFit.tight,
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
              // The colour alone would be the only thing saying which of a set
              // of alternatives is current, and a theme is free to make its
              // accent quiet. `IntrinsicWidth` sizes the card to the widest
              // row, so this pushes every row out by the same amount rather
              // than making the checked one wider than its neighbours.
              if (entry.selected || entry.selectable) ...[
                const SizedBox(width: 12),
                // Transparent rather than absent on an unselected member of a
                // set, so every row of it is as wide as the checked one.
                ShellIcon(
                  ShellGlyph.check,
                  size: 10,
                  color: entry.selected
                      ? foreground
                      : const Color(0x00000000),
                ),
              ],
              if (entry.checked case final on?) ...[
                const SizedBox(width: 12),
                _MenuSwitch(on: on, enabled: entry.enabled),
              ],
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
    this.selectionCount = 1,
  });

  final DesktopItem item;
  final VoidCallback onOpen;
  final void Function(AppEntry handler) onOpenWith;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  /// How many icons the menu acts on. Greater than one when the user
  /// right-clicked a member of a band selection — [item] is then just the one
  /// under the cursor, and the callbacks are the host's to fan out.
  ///
  /// A right-click on a *non*-member needs no special case: the press has already
  /// narrowed the selection to that icon, so the count is 1.
  final int selectionCount;

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

    // Several icons selected: the rows that only make sense for one are absent
    // rather than disabled, the rule "Open with…" already follows for apps.
    // "Open with…" because a selection can span kinds and there is no single
    // item to resolve handlers for; "Rename" because renaming is in-place
    // editing of one label.
    final multiple = widget.selectionCount > 1;

    // "Open with" is meaningless for an application, so the row is absent
    // rather than disabled — there is nothing for it to mean.
    final canOpenWith = !multiple && widget.item.kind != DesktopItemKind.app;

    return DesktopMenuCard(
      entries: [
        DesktopMenuEntry(
          label: multiple ? 'Open ${widget.selectionCount} items' : 'Open',
          icon: ShellGlyph.externalLink,
          onTap: widget.onOpen,
        ),
        if (canOpenWith)
          DesktopMenuEntry(
            label: 'Open with…',
            icon: ShellGlyph.listUl,
            onTap: () => setState(() => _handlers = widget.handlers()),
          ),
        if (!multiple)
          DesktopMenuEntry(
            label: 'Rename',
            icon: ShellGlyph.edit,
            onTap: widget.onRename,
          ),
        DesktopMenuEntry(
          label: multiple
              ? 'Remove ${widget.selectionCount} items from desktop'
              : 'Remove from desktop',
          icon: ShellGlyph.trash,
          onTap: widget.onRemove,
        ),
      ],
    );
  }
}

/// The menu shown on right-clicking bare desktop.
///
/// Two pages, like [DesktopItemMenu] and for the same reason: "Add widget…" lists
/// whatever `DesktopWidgetRegistry` holds, and a child popup would be a second
/// Wayland surface for a list mutually exclusive with the page behind it.
class DesktopEmptyMenu extends StatefulWidget {
  const DesktopEmptyMenu({
    super.key,
    required this.onAddApplication,
    required this.onAddFile,
    required this.onOrganize,
    required this.onChangeBackground,
    this.widgetSpecs = const [],
    this.onAddWidget,
    this.onOpenDesktopSettings,
    this.onOpenSettings,
  });

  final VoidCallback onAddApplication;
  final VoidCallback onAddFile;

  /// Compacts the *icons*. Widgets are deliberately left where they are — see
  /// [DesktopWidgetItem].
  final VoidCallback onOrganize;
  final VoidCallback onChangeBackground;

  /// What "Add widget…" offers, passed in rather than read from the registry:
  /// the registry is process-global, and a menu that reached for it could not
  /// be pumped in a widget test without one.
  final List<DesktopWidgetSpec> widgetSpecs;

  /// Null, or an empty [widgetSpecs], hides the row entirely — a build with no
  /// widget types has nothing to offer, and a disabled row would be a promise
  /// with nothing behind it.
  final void Function(DesktopWidgetSpec spec)? onAddWidget;

  /// "Desktop settings…" — Shell › Desktop Grid. Null hides the row.
  final VoidCallback? onOpenDesktopSettings;

  /// "Settings…" — the settings overlay's landing page, which a right-click on
  /// bare desktop always offers. Null hides the row, for a test that pumps the
  /// menu with no shell behind it.
  final VoidCallback? onOpenSettings;

  @override
  State<DesktopEmptyMenu> createState() => _DesktopEmptyMenuState();
}

class _DesktopEmptyMenuState extends State<DesktopEmptyMenu> {
  bool _choosingWidget = false;

  @override
  Widget build(BuildContext context) {
    final onAddWidget = widget.onAddWidget;
    final specs = widget.widgetSpecs;

    if (_choosingWidget && onAddWidget != null) {
      return DesktopMenuCard(
        header: 'Add widget',
        onBack: () => setState(() => _choosingWidget = false),
        entries: [
          for (final spec in specs)
            DesktopMenuEntry(
              label: spec.name,
              icon: spec.icon,
              onTap: () => onAddWidget(spec),
            ),
        ],
      );
    }

    return DesktopMenuCard(
      entries: [
        DesktopMenuEntry(
          label: 'Add application…',
          icon: ShellGlyph.rocket,
          onTap: widget.onAddApplication,
        ),
        DesktopMenuEntry(
          label: 'Add file or folder…',
          icon: ShellGlyph.folderOpen,
          onTap: widget.onAddFile,
        ),
        if (onAddWidget != null && specs.isNotEmpty)
          DesktopMenuEntry(
            label: 'Add widget…',
            icon: ShellGlyph.shapes,
            onTap: () => setState(() => _choosingWidget = true),
          ),
        DesktopMenuEntry(
          label: 'Organize',
          icon: ShellGlyph.grid,
          onTap: widget.onOrganize,
        ),
        DesktopMenuEntry(
          label: 'Change background…',
          icon: ShellGlyph.image,
          onTap: widget.onChangeBackground,
        ),
        ...settingsLinks(
          desktop: widget.onOpenDesktopSettings,
          settings: widget.onOpenSettings,
        ),
      ],
    );
  }
}

/// The links to settings that close a desktop menu, behind a divider: the
/// desktop's own page, and the overlay's landing page. Empty when neither is
/// given.
List<DesktopMenuItem> settingsLinks({
  VoidCallback? desktop,
  VoidCallback? settings,
}) => [
  if (desktop != null || settings != null) const DesktopMenuDivider(),
  if (desktop != null)
    DesktopMenuEntry(
      label: 'Desktop settings…',
      icon: ShellGlyph.grid,
      onTap: desktop,
    ),
  if (settings != null)
    DesktopMenuEntry(
      label: 'Settings…',
      icon: ShellGlyph.settings,
      onTap: settings,
    ),
];

/// The menu shown on right-clicking the wallpaper of an output whose desktop
/// grid is switched off, so there are no icons or widgets to add — but a
/// right-click on bare background still always reaches Settings.
class DesktopBackgroundMenu extends StatelessWidget {
  const DesktopBackgroundMenu({
    super.key,
    required this.onChangeBackground,
    required this.onOpenSettings,
  });

  final VoidCallback onChangeBackground;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => DesktopMenuCard(
    entries: [
      DesktopMenuEntry(
        label: 'Change background…',
        icon: ShellGlyph.image,
        onTap: onChangeBackground,
      ),
      ...settingsLinks(settings: onOpenSettings),
    ],
  );
}

/// The menu shown on right-clicking a desktop widget.
///
/// Deliberately short. A widget is resized by its grips and moved by dragging
/// it, so the menu carries the two things a pointer cannot express: putting a
/// widget back to the size its type ships with, and removing it.
class DesktopWidgetMenu extends StatelessWidget {
  const DesktopWidgetMenu({
    super.key,
    required this.item,
    required this.spec,
    required this.onRemove,
    this.onResetSize,
    this.quickSettings = const [],
    this.settingsLabel,
    this.onOpenWidgetSettings,
  });

  final DesktopWidgetItem item;

  /// Null when the config names a type this build does not have — the
  /// placeholder still has to be removable.
  final DesktopWidgetSpec? spec;

  final VoidCallback onRemove;
  final VoidCallback? onResetSize;

  /// The widget's options worth changing in place, already turned into rows
  /// (see `quickSettingItems`) — drawn above the widget's own actions.
  final List<DesktopMenuItem> quickSettings;

  /// The row that opens the page configuring this widget — "Weather
  /// settings…" — and what it does. Either null hides it.
  final String? settingsLabel;
  final VoidCallback? onOpenWidgetSettings;

  @override
  Widget build(BuildContext context) {
    final spec = this.spec;
    final onOpenWidgetSettings = this.onOpenWidgetSettings;
    final atDefault = spec != null &&
        item.columnSpan == spec.defaultSpan.columns &&
        item.rowSpan == spec.defaultSpan.rows;

    return DesktopMenuCard(
      header: spec?.name ?? item.type,
      entries: [
        if (quickSettings.isNotEmpty) ...[
          ...quickSettings,
          const DesktopMenuDivider(),
        ],
        if (spec != null && onResetSize != null)
          DesktopMenuEntry(
            label: 'Reset size',
            icon: ShellGlyph.compress,
            // Shown greyed rather than hidden at the default size, the rule
            // [DesktopMenuEntry.enabled] exists for: the menu keeps its shape.
            enabled: !atDefault,
            onTap: onResetSize!,
          ),
        DesktopMenuEntry(
          label: 'Remove widget',
          icon: ShellGlyph.trash,
          onTap: onRemove,
        ),
        if (settingsLabel != null && onOpenWidgetSettings != null) ...[
          const DesktopMenuDivider(),
          DesktopMenuEntry(
            label: settingsLabel!,
            icon: ShellGlyph.settings,
            onTap: onOpenWidgetSettings,
          ),
        ],
      ],
    );
  }
}
