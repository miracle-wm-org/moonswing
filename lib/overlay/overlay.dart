// ignore_for_file: library_private_types_in_public_api

import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/calendar_tab.dart';
import 'package:graceful_shell/overlay/settings/audio.dart';
import 'package:graceful_shell/overlay/settings/bluetooth.dart';
import 'package:graceful_shell/overlay/settings/display.dart';
import 'package:graceful_shell/overlay/settings/network.dart';
import 'package:graceful_shell/overlay/settings/shell.dart';
import 'package:graceful_shell/overlay/settings_route.dart';
import 'package:graceful_shell/overlay/system/system_tab.dart';
import 'package:graceful_shell/overlay/system_info/system_info_tab.dart';
import 'package:graceful_shell/scopes.dart';

/// The panel is a share of the display rather than a fixed box, so it reads the
/// same on a 1080p laptop and on a 4K desktop. 16:10 is a little squarer than
/// the 16:9 of most monitors, which suits the sidebar-plus-content layout and
/// keeps the panel clear of the screen edges on a wide display.
const double kOverlayPanelAspect = 16 / 10;
const double kOverlayPanelWidthFraction = 0.66;
const double kOverlayPanelHeightFraction = 0.78;
const Size kOverlayPanelMinSize = Size(800, 800 / kOverlayPanelAspect);
const Size kOverlayPanelMaxSize = Size(1600, 1600 / kOverlayPanelAspect);

/// Panel size for an overlay surface of [available] logical pixels. The overlay
/// window is anchored to all four edges (see `_openOverlay` in
/// `modules/clock.dart`), so [available] is the usable size of the monitor.
///
/// Every clamp re-derives the other axis from [kOverlayPanelAspect], so the
/// ratio survives all of them — except the last one, where fitting on screen
/// wins over the minimum size.
Size overlayPanelSize(Size available) {
  double width = available.width * kOverlayPanelWidthFraction;
  double height = width / kOverlayPanelAspect;

  final maxHeight = available.height * kOverlayPanelHeightFraction;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * kOverlayPanelAspect;
  }

  if (width > kOverlayPanelMaxSize.width) {
    width = kOverlayPanelMaxSize.width;
    height = width / kOverlayPanelAspect;
  }
  if (width < kOverlayPanelMinSize.width) {
    width = kOverlayPanelMinSize.width;
    height = width / kOverlayPanelAspect;
  }

  return Size(
    width.clamp(0.0, available.width),
    height.clamp(0.0, available.height),
  );
}

/// One top-level tab in the overlay. Adding a tab is one entry here plus one
/// child in the [IndexedStack] that [_SettingsOverlayState] builds.
class _OverlayTab {
  const _OverlayTab({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final FaIconData icon;
}

const List<_OverlayTab> _tabs = [
  _OverlayTab(
    id: 'calendar',
    label: 'Calendar',
    icon: FontAwesomeIcons.calendarDays,
  ),
  _OverlayTab(
    id: 'system',
    label: 'Monitor',
    icon: FontAwesomeIcons.microchip,
  ),
  _OverlayTab(
    id: 'systeminfo',
    label: 'System Info',
    icon: FontAwesomeIcons.circleInfo,
  ),
  _OverlayTab(
    id: 'settings',
    label: 'Settings',
    icon: FontAwesomeIcons.gear,
  ),
];

class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    this.route,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Where to open. Null keeps the historical behaviour — the calendar tab,
  /// which is what clicking the clock most plausibly means.
  final SettingsRoute? route;

  @override
  _SettingsOverlayState createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  final _focusNode = FocusNode();

  // The animated panel lives inside an Overlay so descendants (e.g. the theme
  // color pickers) can float OverlayPortal popups. Overlay does not rebuild its
  // initial entries on setState, so we keep a handle and markNeedsBuild() it
  // whenever the visible content changes (see [_selectCategory]).
  late final OverlayEntry _panelEntry;

  // Clicking the clock most plausibly means "show me the calendar", so that is
  // the tab the overlay opens on when no route asked for somewhere else.
  late String _selectedTab;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    // Seeded once. The body is an IndexedStack built inside an Overlay entry,
    // so a route is a starting point rather than a live address — the root
    // reopens the overlay to retarget it.
    _selectedTab = widget.route?.tab ?? 'calendar';
    _selectedCategory = widget.route?.category ?? 'network';
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _panelEntry = OverlayEntry(
      builder: (context) => _buildAnimated(ThemeScope.of(context)),
    );
    _controller.forward();
    widget.closingNotifier.addListener(_onClosingChanged);
  }

  void _selectCategory(String cat) {
    _selectedCategory = cat;
    _panelEntry.markNeedsBuild();
  }

  void _selectTab(String tab) {
    _selectedTab = tab;
    _panelEntry.markNeedsBuild();
  }

  void _onClosingChanged() {
    if (widget.closingNotifier.value) {
      _controller.reverse().then((_) => widget.onClosed());
    }
  }

  void _requestClose() {
    widget.closingNotifier.value = true;
  }

  @override
  void dispose() {
    widget.closingNotifier.removeListener(_onClosingChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      // The shell boots without a WidgetsApp/MaterialApp, so the default
      // text-editing key bindings (Backspace, Delete, arrows, Home/End,
      // Ctrl+A, …) that WidgetsApp normally supplies are absent. Provide them
      // here so every EditableText in the settings UI — including the
      // color-picker popup, which is inserted into the Overlay below — handles
      // editing keys instead of dropping them.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 14,
            color: theme.popupForeground,
          ),
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _requestClose();
              }
            },
            child: Overlay(initialEntries: [_panelEntry]),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimated(ThemeConfig theme) {
    // LayoutBuilder outside AnimatedBuilder, so the panel is sized once per
    // surface-size change rather than on every frame of the open animation.
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scrim = Container(
              color: theme.scrim,
              child: Center(
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            );
            return Opacity(
              opacity: _opacity.value,
              // The filter only reaches what Flutter has drawn behind it, and
              // on a transparent layer-shell surface that is nothing — the
              // desktop belongs to the compositor. It is kept because it does
              // soften the scrim under the panel, and skipped entirely at 0 so
              // a theme that sets `blur = 0` pays nothing for it.
              child: theme.blur > 0
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: theme.blur, sigmaY: theme.blur),
                      child: scrim,
                    )
                  : scrim,
            );
          },
          child: _buildPanel(theme, overlayPanelSize(constraints.biggest)),
        );
      },
    );
  }

  Widget _buildPanel(ThemeConfig theme, Size size) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: the tab bar, plus the close button.
          Container(
            padding:
                const EdgeInsets.only(left: 16, right: 12, top: 8, bottom: 0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.divider),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (final tab in _tabs)
                        _TabButton(
                          tab: tab,
                          selected: _selectedTab == tab.id,
                          onTap: () => _selectTab(tab.id),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _requestClose,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: const Color(0x00000000),
                        ),
                        child: Center(
                          child: Text(
                            '✕',
                            style: TextStyle(
                              fontSize: 16,
                              color:
                                  theme.popupForeground.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body. An IndexedStack rather than a switch: the settings tab hosts
          // ShellSettingsPage, which owns a nested Navigator. Rebuilding the
          // body on every tab change would tear that down, dropping the user
          // back to the category landing page — and would lose the calendar's
          // selected month and day the same way.
          //
          // The flip side is that every tab stays alive once built, so a tab
          // that polls must be told when it is not the visible one and stop.
          // That is what SystemTab.active is for.
          Expanded(
            child: IndexedStack(
              index: _tabs.indexWhere((t) => t.id == _selectedTab),
              sizing: StackFit.expand,
              children: [
                const CalendarTab(),
                SystemTab(active: _selectedTab == 'system'),
                const SystemInfoTab(),
                _buildSettingsBody(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBody(ThemeConfig theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSidebar(
          selectedCategory: _selectedCategory,
          onCategorySelected: _selectCategory,
        ),
        Container(width: 1, color: theme.divider),
        Expanded(child: _buildCategoryContent(_selectedCategory)),
      ],
    );
  }

  Widget _buildCategoryContent(String category) {
    switch (category) {
      case 'network':
        return const NetworkSettingsPage();
      case 'bluetooth':
        return const BluetoothSettingsPage();
      case 'display':
        return const DisplaySettingsPage();
      case 'audio':
        return const AudioSettingsPage();
      case 'shell':
        return ShellSettingsPage(
          initialCategory: widget.route?.shellCategory,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _OverlayTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color foreground;
    if (widget.selected) {
      foreground = theme.accent;
    } else if (_hovered) {
      foreground = theme.popupForeground;
    } else {
      foreground = theme.popupForeground.withValues(alpha: 0.6);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            // The underline sits on the header's bottom border, so the selected
            // tab reads as continuous with the content below it.
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(widget.tab.icon, size: 13, color: foreground),
              const SizedBox(width: 8),
              Text(
                widget.tab.label,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: theme.fontFamily,
                  color: foreground,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarItem(
              icon: FontAwesomeIcons.wifi,
              label: 'Network',
              selected: selectedCategory == 'network',
              onTap: () => onCategorySelected('network'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.bluetooth,
              label: 'Bluetooth',
              selected: selectedCategory == 'bluetooth',
              onTap: () => onCategorySelected('bluetooth'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.display,
              label: 'Display',
              selected: selectedCategory == 'display',
              onTap: () => onCategorySelected('display'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.volumeHigh,
              label: 'Audio',
              selected: selectedCategory == 'audio',
              onTap: () => onCategorySelected('audio'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.gear,
              label: 'Shell',
              selected: selectedCategory == 'shell',
              onTap: () => onCategorySelected('shell'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _SidebarItemState createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.selected) {
      bg = theme.accent.withValues(alpha: 0.25);
    } else if (_hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = const Color(0x00000000);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              FaIcon(
                widget.icon,
                size: 13,
                color: widget.selected
                    ? theme.accent
                    : theme.popupForeground.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: widget.selected
                      ? theme.accent
                      : theme.popupForeground.withValues(alpha: 0.8),
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
