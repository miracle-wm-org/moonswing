// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/underline_tabs.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/calendar/calendar_tab.dart';
import 'package:graceful_shell/overlay/settings/audio.dart';
import 'package:graceful_shell/overlay/settings/bluetooth.dart';
import 'package:graceful_shell/overlay/settings/display.dart';
import 'package:graceful_shell/overlay/settings/keyboard.dart';
import 'package:graceful_shell/overlay/settings/miracle.dart';
import 'package:graceful_shell/overlay/settings/network.dart';
import 'package:graceful_shell/overlay/settings/settings_highlight.dart';
import 'package:graceful_shell/overlay/settings/settings_search.dart';
import 'package:graceful_shell/overlay/settings/settings_search_bar.dart';
import 'package:graceful_shell/overlay/settings/shell.dart';
import 'package:graceful_shell/overlay/settings_route.dart';
import 'package:graceful_shell/overlay/system/system_tab.dart';
import 'package:graceful_shell/overlay/system_info/system_info_tab.dart';
import 'package:graceful_shell/hover_region.dart';
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
/// window is anchored to all four edges, so [available] is the usable size of the
/// monitor.
///
/// Every clamp re-derives the other axis from [kOverlayPanelAspect], so the ratio
/// survives all of them — except the last, where fitting on screen wins over the
/// minimum size.
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

/// The panel's base fill: [ThemeConfig.popupBackground], always opaque.
///
/// A theme's `popup_background` carries its author's alpha, which is right for a
/// three-row menu over the desktop and wrong for this panel: a workspace of small
/// text, chart strokes and form fields, all of which the translucency costs. Only
/// the alpha is overridden, so a theme still colours the panel. Depth comes from
/// the scrim [FadeOverlayScaffold] paints behind it instead.
Color overlayPanelFill(ThemeConfig theme) => opaquePopupFill(theme);

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
  _OverlayTab(id: 'system', label: 'Monitor', icon: FontAwesomeIcons.microchip),
  _OverlayTab(
    id: 'systeminfo',
    label: 'System Info',
    icon: FontAwesomeIcons.circleInfo,
  ),
  _OverlayTab(id: 'settings', label: 'Settings', icon: FontAwesomeIcons.gear),
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

class _SettingsOverlayState extends State<SettingsOverlay> {
  final _focusNode = FocusNode();

  // Where a picked search result is published, and who is listening for it:
  // the Shell pane pushes the category's route, its category view holds that
  // page mounted while the jump lands, and the row itself scrolls into view
  // and pulses. Owned here rather than being a singleton, because it is a
  // property of *this open overlay* — see [SettingsHighlightController].
  final SettingsHighlightController _highlight = SettingsHighlightController();

  // Owned here so Ctrl+F from anywhere in the panel reaches the field, which
  // is the shortcut the file picker's own search box already answers to.
  final FocusNode _searchFocus = FocusNode();

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
    _panelEntry = OverlayEntry(
      builder: (context) {
        final theme = ThemeScope.of(context);
        return FadeOverlayScaffold(
          closing: widget.closingNotifier,
          onClosed: widget.onClosed,
          // Statelier than the rest, as it has always been, but as a
          // proportion of the theme's pace rather than a duration of its own:
          // this is the one overlay that is a workspace rather than a card the
          // pointer is chasing, and `overlay_animation_duration` still moves it
          // with everything else. [ShellDurations.overlayEntrance] over
          // [ShellDurations.overlayFade] is the ratio that keeps the shipped
          // themes playing exactly what they played before.
          durationScale: ShellDurations.overlayEntrance.inMilliseconds /
              ShellDurations.overlayFade.inMilliseconds,
          // No backdrop-tap dismiss, deliberately: the settings panel is a
          // workspace, and a stray click on the scrim losing an in-progress
          // edit would be worse than needing Escape or the close button.
          child: LayoutBuilder(
            // As the scaffold's child this is built once per surface-size
            // change, not on every animation frame.
            builder: (context, constraints) =>
                _buildPanel(theme, overlayPanelSize(constraints.biggest)),
          ),
        );
      },
    );
  }

  void _selectCategory(String cat) {
    _selectedCategory = cat;
    _panelEntry.markNeedsBuild();
  }

  void _selectTab(String tab) {
    _selectedTab = tab;
    _panelEntry.markNeedsBuild();
  }

  void _requestClose() {
    widget.closingNotifier.value = true;
  }

  /// Takes the user to [field]: the tab, the sidebar category and — through
  /// [_highlight] — the Shell pane's route and the row itself.
  ///
  /// The three moves are separate because the three pieces of state are: the tab
  /// and category are this widget's, while the pane's route is a nested
  /// `Navigator`'s and a row's offset is a `Scrollable`'s.
  void _jumpToSetting(SettingsField field) {
    _selectedTab = field.route.tab;
    _selectedCategory = field.route.category;
    // Published *before* the rebuild, so a Shell pane being built for the
    // first time — the user was on Audio, say — can seed its initial route
    // from the pending target instead of landing on the category list.
    if (field.highlights ||
        field.route.shellCategory != null ||
        field.route.miracleCategory != null) {
      _highlight.jumpTo(field);
    }
    _panelEntry.markNeedsBuild();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchFocus.dispose();
    _highlight.dispose();
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
              if (event is! KeyDownEvent) return;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _requestClose();
                return;
              }
              // Ctrl+F focuses the settings search, which is the binding
              // `file_picker.dart` already answers to for its own search box.
              // Read here rather than on the field because this listener is
              // the panel's root, so it sees the key wherever the pointer and
              // the focus happen to be; it is gated on the tab because the
              // search bar is the Settings tab's alone.
              if (event.logicalKey == LogicalKeyboardKey.keyF &&
                  HardwareKeyboard.instance.isControlPressed &&
                  _selectedTab == 'settings') {
                _searchFocus.requestFocus();
              }
            },
            // Every popup this window opens paints opaque, whatever alpha
            // the theme gives `popup_background`: the dropdowns, the colour
            // picker, the confirmations and the file picker all float over
            // the panel's own dense text, and a see-through card over it
            // leaves neither layer readable. Above the Overlay rather than
            // inside the panel, because that is where `showRootModal` and
            // every `AnchoredSearchDropdown` insert their cards.
            // Above the Overlay, so the panel *and* everything floating
            // over it can read the pending jump — the results card is a
            // sibling of the pane it sends the user to.
            child: SettingsHighlightScope(
              controller: _highlight,
              child: OpaquePopupScope(
                child: Overlay(initialEntries: [_panelEntry]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(ThemeConfig theme, Size size) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: overlayPanelFill(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: the tab bar, plus the close button.
          Container(
            padding: const EdgeInsets.only(
              left: 16,
              right: 12,
              top: 8,
              bottom: 0,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.divider)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (final tab in _tabs)
                        UnderlineTab(
                          label: tab.label,
                          icon: tab.icon,
                          selected: _selectedTab == tab.id,
                          onTap: () => _selectTab(tab.id),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: HoverRegion(
                    onTap: _requestClose,
                    builder: (context, hovered) => Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(ShellRadii.control),
                        color: hovered
                            ? theme.surfaceHover
                            : const Color(0x00000000),
                      ),
                      child: Center(
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: ShellFontSizes.title,
                            color: theme.popupForeground.withValues(
                              alpha: hovered ? 0.9 : 0.6,
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
          // That is what SystemTab.active and CalendarTab.active are for — the
          // latter drives the world clocks' one-second timer.
          Expanded(
            child: IndexedStack(
              index: _tabs.indexWhere((t) => t.id == _selectedTab),
              sizing: StackFit.expand,
              children: [
                CalendarTab(active: _selectedTab == 'calendar'),
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
    // The search bar is a `Stack` child over the body rather than a row above
    // it, and the body indents by [kSettingsSearchBarHeight] to make room. Two
    // reasons, and both are about not moving what the user is reading: the
    // results card hangs *over* the pane it is about to send them to instead
    // of displacing it, and the panes themselves are laid out exactly as they
    // were before the field existed.
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: kSettingsSearchBarHeight),
            Container(height: 1, color: theme.divider),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSidebar(
                    selectedCategory: _selectedCategory,
                    onCategorySelected: _selectCategory,
                  ),
                  Container(width: 1, color: theme.divider),
                  Expanded(child: _buildCategoryContent(_selectedCategory)),
                ],
              ),
            ),
          ],
        ),
        // Fills the body rather than sitting in its corner: the bar draws its
        // field at the top left and, while results are open, a dismiss barrier
        // over everything else. It costs the panes nothing at rest — see
        // [SettingsSearchBar].
        Positioned.fill(
          child: SettingsSearchBar(
            focusNode: _searchFocus,
            onJump: _jumpToSetting,
          ),
        ),
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
      case 'keyboard':
        return const KeyboardSettingsPage();
      case 'miracle':
        return MiracleSettingsPage(
          initialCategory: widget.route?.miracleCategory,
        );
      case 'shell':
        return ShellSettingsPage(initialCategory: widget.route?.shellCategory);
      default:
        return const SizedBox.shrink();
    }
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
              icon: FontAwesomeIcons.keyboard,
              label: 'Keyboard',
              selected: selectedCategory == 'keyboard',
              onTap: () => onCategorySelected('keyboard'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.wandMagicSparkles,
              label: 'Window Manager',
              selected: selectedCategory == 'miracle',
              onTap: () => onCategorySelected('miracle'),
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

class _SidebarItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final Color bg;
        if (selected) {
          bg = theme.accent.withValues(alpha: 0.25);
        } else if (hovered) {
          bg = theme.surfaceHover;
        } else {
          bg = const Color(0x00000000);
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Row(
            children: [
              FaIcon(
                icon,
                size: ShellFontSizes.body,
                color: selected
                    ? theme.accent
                    : theme.popupForeground.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  color: selected
                      ? theme.accent
                      : theme.popupForeground.withValues(alpha: 0.8),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
