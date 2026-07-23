// The dock's app-directory button and its popup.
//
// [AppDirectoryButton] sits at the right edge of the dock (after a divider).
// Tapping it opens a [PopupWindow] (via [PopupHost]) listing every installed
// application, with global type-to-search. Categories are browsed by hovering:
// each category opens a child popup (a flyout) anchored to its right, flipping
// to the left when there is not enough room. Right-clicking an app offers "Pin
// to dock", which appends its id to `[modules.dock].apps` in the shared
// [ConfigStore] — the running dock then reloads live.

// WindowPositionerAnchor is re-exported from layer_shell but marked @internal.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:layer_shell/layer_shell.dart' show WindowPositionerAnchor;

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';

/// The dock's right-side button that opens the application directory.
class AppDirectoryButton extends StatefulWidget {
  const AppDirectoryButton({super.key, required this.iconSize});

  final int iconSize;

  @override
  State<AppDirectoryButton> createState() => _AppDirectoryButtonState();
}

class _AppDirectoryButtonState extends State<AppDirectoryButton>
    with PopupHost<AppDirectoryButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _toggle(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    final theme = ThemeScope.of(context);
    openBarPopup(
      context,
      // Width is fixed (the search field / list rows need a bounded width);
      // height sizes to content, capped high so only a very long list scrolls.
      preferredConstraints: const BoxConstraints(
        minWidth: 300,
        maxWidth: 300,
        maxHeight: 1200,
      ),
      child: ThemeScope(
        theme: theme,
        child: PopupBounceIn(
          child: _AppDirectory(
            theme: theme,
            iconSize: widget.iconSize,
            onClose: closePopup,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    Color color = const Color(0x00000000);
    if (_pressed || isPopupOpen) {
      color = theme.surfacePressed;
    } else if (_hovered) {
      color = theme.surfaceHover;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _toggle(context);
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            width: widget.iconSize.toDouble(),
            height: widget.iconSize.toDouble(),
            child: Center(
              child: FaIcon(
                FontAwesomeIcons.tableCellsLarge,
                size: widget.iconSize * 0.72,
                color: theme.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The popup body: a search field over a category browser. Hovering a category
/// opens a child flyout popup listing its apps; typing replaces the category
/// list with a flat, global search result. Owns the submenu popup via
/// [PopupHost].
class _AppDirectory extends StatefulWidget {
  const _AppDirectory({
    required this.theme,
    required this.iconSize,
    required this.onClose,
  });

  final ThemeConfig theme;
  final int iconSize;
  final VoidCallback onClose;

  @override
  State<_AppDirectory> createState() => _AppDirectoryState();
}

class _AppDirectoryState extends State<_AppDirectory>
    with PopupHost<_AppDirectory> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'app-directory-search');

  List<AppEntry> _apps = const [];
  final Map<String, List<AppEntry>> _byCategory = {};
  List<String> _categories = const [];

  String _query = '';
  String? _submenuCategory; // category whose flyout is currently open
  Timer? _closeTimer;
  // A pin popup (child of the open flyout) suspends the flyout's auto-close:
  // the pointer sits on that separate surface, which would otherwise read as
  // having left the flyout.
  bool _pinMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _apps = loadInstalledApps();
    for (final app in _apps) {
      _byCategory.putIfAbsent(mainCategoryOf(app), () => []).add(app);
    }
    _categories = _byCategory.keys.toList()
      ..sort((a, b) {
        // Keep "Other" last, everything else alphabetical.
        if (a == kOtherCategory) return 1;
        if (b == kOtherCategory) return -1;
        return a.compareTo(b);
      });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    closePopup();
    _searchController.dispose();
    _searchFocus.dispose();
    disposeAppEntries(_apps);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (isPopupOpen) {
        _closeSubmenu();
      } else if (_query.isNotEmpty) {
        setState(() {
          _query = '';
          _searchController.clear();
        });
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _launch(AppEntry app) {
    launchApp(app.appInfo);
    widget.onClose();
  }

  void _pin(AppEntry app) {
    final store = ConfigStore.instance;
    final list = store.getList<String>(['modules', 'dock', 'apps']);
    if (!list.contains(app.id)) {
      store.set(['modules', 'dock', 'apps'], [...list, app.id]);
    }
  }

  // --- Category flyout (child popup) lifecycle -------------------------------

  void _cancelClose() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void _scheduleClose() {
    if (_pinMenuOpen) return; // keep the flyout up while its pin popup is open
    _closeTimer?.cancel();
    // A short grace period lets the pointer travel from the category row into
    // the flyout (a separate window) without the flyout closing underneath it.
    _closeTimer = Timer(const Duration(milliseconds: 180), _closeSubmenu);
  }

  void _closeSubmenu() {
    _cancelClose();
    if (isPopupOpen) closePopup();
    if (mounted) setState(() => _submenuCategory = null);
  }

  void _openSubmenu(BuildContext rowContext, String category) {
    _cancelClose();
    if (_submenuCategory == category && isPopupOpen) return;
    // Switch flyouts: drop the current one before anchoring the next.
    if (isPopupOpen) closePopup();
    _submenuCategory = category;

    final theme = widget.theme;
    final apps = _byCategory[category] ?? const [];
    openPopup(
      rowContext,
      anchorRect: popupAnchorRect(rowContext),
      // Anchor to the row's right edge; flip to the left when out of room.
      parentAnchor: WindowPositionerAnchor.topRight,
      childAnchor: WindowPositionerAnchor.topLeft,
      constraintAdjustment: kPopupFlipX,
      // Fixed width; height sizes to content, capped high so only a very long
      // list scrolls.
      preferredConstraints: const BoxConstraints(
        minWidth: 240,
        maxWidth: 240,
        maxHeight: 1200,
      ),
      // The flyout is its own popup window, so it does not inherit the
      // Directionality / DefaultTextStyle from the directory popup's tree.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(
            color: theme.popupForeground,
            fontFamily: theme.fontFamily,
            fontSize: 13,
          ),
          child: ThemeScope(
            theme: theme,
            child: MouseRegion(
                onEnter: (_) => _cancelClose(),
                onExit: (_) => _scheduleClose(),
                child: _FlyoutCard(
                  theme: theme,
                  child: _AppListView(
                    apps: apps,
                    theme: theme,
                    iconSize: widget.iconSize,
                    onLaunch: _launch,
                    onPin: _pin,
                    onMenuOpened: () {
                      _pinMenuOpen = true;
                      _cancelClose();
                    },
                    onMenuClosed: () {
                      _pinMenuOpen = false;
                      _scheduleClose();
                    },
                  ),
              ),
            ),
          ),
        ),
      ),
    );
    setState(() {});
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    // Category flyouts only make sense while browsing categories.
    if (value.isNotEmpty && isPopupOpen) _closeSubmenu();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final searching = _query.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.ltr,
      // No WidgetsApp is mounted, so supply the default text-editing key
      // bindings the search field relies on.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            color: theme.popupForeground,
            fontFamily: theme.fontFamily,
            fontSize: 13,
          ),
          child: Focus(
            onKeyEvent: _onKey,
            child: Container(
              decoration: BoxDecoration(
                color: theme.popupBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: searching
                        ? _AppListView(
                            apps: _searchResults(),
                            theme: theme,
                            iconSize: widget.iconSize,
                            onLaunch: _launch,
                            onPin: _pin,
                          )
                        : _buildCategoryList(theme),
                  ),
                  const SizedBox(height: 8),
                  _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    theme: theme,
                    hint: 'Search apps…',
                    onChanged: _onSearchChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<AppEntry> _searchResults() {
    final q = _query.toLowerCase();
    return _apps.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  Widget _buildCategoryList(ThemeConfig theme) {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        final count = _byCategory[cat]!.length;
        final active = _submenuCategory == cat && isPopupOpen;
        return _MenuRow(
          theme: theme,
          label: cat,
          active: active,
          onTap: () {}, // Categories are opened by hover, not click.
          onEnter: (ctx) => _openSubmenu(ctx, cat),
          onExit: () => _scheduleClose(),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count',
                  style: TextStyle(color: theme.muted, fontSize: 11)),
              const SizedBox(width: 6),
              FaIcon(FontAwesomeIcons.chevronRight,
                  size: 10, color: theme.muted),
            ],
          ),
        );
      },
    );
  }
}

/// Rounded, themed card wrapping a category flyout's contents.
class _FlyoutCard extends StatelessWidget {
  const _FlyoutCard({required this.theme, required this.child});

  final ThemeConfig theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.divider, width: 1),
      ),
      padding: const EdgeInsets.all(6),
      child: child,
    );
  }
}

/// A scrolling list of app rows: left-click launches, right-click opens a real
/// child "Pin to dock" popup anchored at the cursor. Reused for both the global
/// search results and each category flyout.
///
/// [onMenuOpened]/[onMenuClosed] bracket the pin popup's lifetime so a host that
/// auto-closes on pointer-exit (the category flyout) can stay open while the
/// pin popup — a separate surface the pointer moves onto — is up.
class _AppListView extends StatefulWidget {
  const _AppListView({
    required this.apps,
    required this.theme,
    required this.iconSize,
    required this.onLaunch,
    required this.onPin,
    this.onMenuOpened,
    this.onMenuClosed,
  });

  final List<AppEntry> apps;
  final ThemeConfig theme;
  final int iconSize;
  final void Function(AppEntry) onLaunch;
  final void Function(AppEntry) onPin;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;

  @override
  State<_AppListView> createState() => _AppListViewState();
}

class _AppListViewState extends State<_AppListView>
    with PopupHost<_AppListView> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _openPinMenu(AppEntry app, Offset windowLocal) {
    if (isPopupOpen) closePopup();
    final theme = widget.theme;
    openPopup(
      context,
      // A zero-size rect at the cursor (in this window's coordinate space);
      // the menu's top-left is placed there and slid to stay on-screen.
      anchorRect: windowLocal & Size.zero,
      parentAnchor: WindowPositionerAnchor.topLeft,
      childAnchor: WindowPositionerAnchor.topLeft,
      constraintAdjustment: kPopupSlide,
      // Loose: the menu sizes to its content (see [ContextMenuCard]).
      preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
      onClosed: widget.onMenuClosed,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(
            color: theme.popupForeground,
            fontFamily: theme.fontFamily,
            fontSize: 13,
          ),
          child: ThemeScope(
            theme: theme,
            child: PopupBounceIn(
              child: ContextMenuCard(
                items: [
                  ContextMenuItem(
                    label: 'Pin to dock',
                    onTap: () {
                      widget.onPin(app);
                      closePopup();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    widget.onMenuOpened?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final apps = widget.apps;

    if (apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('No applications',
              style: TextStyle(color: theme.muted, fontSize: 12)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        return _MenuRow(
          theme: theme,
          leading: AppIconImage(
            iconName: app.iconName,
            name: app.name,
            size: 18,
            foreground: theme.popupForeground,
          ),
          label: app.name,
          onTap: () => widget.onLaunch(app),
          onSecondaryTapDown: (d) => _openPinMenu(app, d.globalPosition),
        );
      },
    );
  }
}

/// Bordered single-line search input backed by [EditableText] with autofocus.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ThemeConfig theme;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.divider, width: 1),
      ),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.magnifyingGlass,
              size: 12, color: theme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? Text(hint,
                          style: TextStyle(color: theme.muted, fontSize: 13))
                      : const SizedBox.shrink(),
                ),
                EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.popupForeground,
                    fontFamily: theme.fontFamily,
                  ),
                  cursorColor: theme.accent,
                  backgroundCursorColor: theme.divider,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A hover-highlighted list row used for both categories and apps.
///
/// [onEnter]/[onExit] fire on pointer transitions (used to drive the category
/// flyouts); [onEnter] receives the row's own [BuildContext] so callers can
/// anchor a popup to it. [active] keeps the row highlighted while its flyout is
/// open even after the pointer has moved into the flyout.
class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.theme,
    required this.label,
    required this.onTap,
    this.leading,
    this.trailing,
    this.onSecondaryTapDown,
    this.onEnter,
    this.onExit,
    this.active = false,
  });

  final ThemeConfig theme;
  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final GestureTapDownCallback? onSecondaryTapDown;
  final void Function(BuildContext rowContext)? onEnter;
  final VoidCallback? onExit;
  final bool active;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final highlight = _hovered || widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call(context);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: highlight ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                SizedBox(width: 18, height: 18, child: widget.leading),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: theme.popupForeground, fontSize: 13),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared context-menu widgets (used here for "Pin" and by the dock for "Unpin")
// ---------------------------------------------------------------------------

/// A single row in a [ContextMenuCard].
class ContextMenuItem {
  const ContextMenuItem({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

/// A rounded, themed context-menu card rendering a column of [ContextMenuItem]s.
/// Reads its theme from the enclosing [ThemeScope], so callers must provide one.
class ContextMenuCard extends StatelessWidget {
  const ContextMenuCard({super.key, required this.items});

  final List<ContextMenuItem> items;

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
        // IntrinsicWidth so the card hugs its widest row (stretch alone would
        // fill the incoming max width), letting the popup size to content.
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
                for (final item in items)
                  _ContextMenuRow(theme: theme, item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextMenuRow extends StatefulWidget {
  const _ContextMenuRow({required this.theme, required this.item});

  final ThemeConfig theme;
  final ContextMenuItem item;

  @override
  State<_ContextMenuRow> createState() => _ContextMenuRowState();
}

class _ContextMenuRowState extends State<_ContextMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.item.onTap,
        child: Container(
          color: _hovered ? theme.surfaceHover : const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(widget.item.label,
              style: TextStyle(color: theme.popupForeground, fontSize: 13)),
        ),
      ),
    );
  }
}
