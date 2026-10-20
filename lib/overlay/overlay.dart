// ignore_for_file: library_private_types_in_public_api

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/keybinds/keybind_cheatsheet.dart';
import 'package:moonswing/miracle_manager.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/underline_tabs.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/calendar/calendar_tab.dart';
import 'package:moonswing/overlay/settings/accounts.dart';
import 'package:moonswing/overlay/settings/audio.dart';
import 'package:moonswing/overlay/settings/bluetooth.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/default_apps.dart';
import 'package:moonswing/overlay/settings/display.dart';
import 'package:moonswing/overlay/settings/keyboard.dart';
import 'package:moonswing/overlay/settings/miracle.dart';
import 'package:moonswing/overlay/settings/network.dart';
import 'package:moonswing/overlay/settings/power.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/overlay/settings/settings_search.dart';
import 'package:moonswing/overlay/settings/settings_search_bar.dart';
import 'package:moonswing/overlay/settings/shell.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/overlay/sticky_notes/overview_actions.dart';
import 'package:moonswing/overlay/sticky_notes/sticky_note_layer.dart';
import 'package:moonswing/overlay/system/system_tab.dart';
import 'package:moonswing/overlay/system_info/system_info_tab.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/tab_focus_traversal.dart';
import 'package:moonswing/todo/todo_board.dart';

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

/// One top-level tab in the overlay. Adding a tab is one entry here, an
/// [OverviewTab] id, and one case in [_SettingsOverlayState._buildTab].
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
    id: OverviewTab.calendar,
    label: 'Calendar',
    icon: FontAwesomeIcons.calendarDays,
  ),
  _OverlayTab(
    id: OverviewTab.system,
    label: 'Monitor',
    icon: FontAwesomeIcons.microchip,
  ),
  _OverlayTab(
    id: OverviewTab.systemInfo,
    label: 'System Info',
    icon: FontAwesomeIcons.circleInfo,
  ),
  _OverlayTab(
    id: OverviewTab.settings,
    label: 'Settings',
    icon: FontAwesomeIcons.gear,
  ),
  // The board and the cheat sheet used to be full-screen windows of their
  // own, opened by their bar buttons. They are tabs so that the overview is
  // the one place a workspace opens: one window, one close, one position.
  _OverlayTab(
    id: OverviewTab.todo,
    label: 'Todo',
    icon: FontAwesomeIcons.listCheck,
  ),
  _OverlayTab(
    id: OverviewTab.shortcuts,
    label: 'Shortcuts',
    icon: FontAwesomeIcons.keyboard,
  ),
];

/// Whether [tab] is one of the overview's tab ids.
bool isOverviewTab(String tab) => _tabs.any((t) => t.id == tab);

/// The overview: the clock's panel, and the window the todo and keyboard
/// buttons open on their own tabs.
///
/// One card on a scrim, moved by dragging its tab strip and never resized.
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    this.route,
    this.tab,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Where to open. Null keeps the historical behaviour — the calendar tab,
  /// which is what clicking the clock most plausibly means.
  final SettingsRoute? route;

  /// The visible tab, shared with the root: this overlay writes every change
  /// of tab into it, and switches to whatever the root writes. It is how a bar
  /// button retargets an open overview in place — or, finding its own tab
  /// already showing, closes it — without the close-and-reopen a [route]
  /// needs.
  final ValueNotifier<String>? tab;

  @override
  _SettingsOverlayState createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  // Listens for Escape and Ctrl+F; never a Tab stop of its own.
  final _focusNode = FocusNode(skipTraversal: true);

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

  /// The tabs that have been shown since the overlay opened. A tab is built
  /// the first time it is visited and kept from then on, so the overview does
  /// not pay for a todo board, a keybind round trip and a process walk every
  /// time somebody clicks the clock to read the date.
  final Set<String> _visited = {};

  /// Where the panel is, as an offset from the centre of the output. Shared
  /// with [FadeOverlayScaffold], which positions the card from it, so a drag
  /// relayouts one box and rebuilds nothing.
  late final ValueNotifier<Offset> _offset = ValueNotifier(_lastOffset);

  /// Where the panel was last left, so the next overview opens there. For the
  /// session only: a position is about the windows on screen right now, and a
  /// remembered one on a smaller monitor is clamped back onto it anyway.
  static Offset _lastOffset = Offset.zero;

  /// How far the panel can move from the centre each way and stay on screen,
  /// as of the last layout.
  Offset _maxOffset = Offset.zero;

  /// The sticky notes around the panel, asked to add one by the corner button
  /// and to close its menu before an Escape closes the overview.
  final GlobalKey<StickyNoteLayerState> _stickyNotes = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Seeded once. The body is an IndexedStack built inside an Overlay entry,
    // so a route is a starting point rather than a live address — the root
    // reopens the overlay to retarget it, except to another tab alone, which
    // goes through [SettingsOverlay.tab].
    final tab = widget.route?.tab;
    _selectedTab = tab != null && isOverviewTab(tab)
        ? tab
        : OverviewTab.calendar;
    widget.tab?.value = _selectedTab;
    widget.tab?.addListener(_onTabRequested);
    _selectedCategory = widget.route?.category ?? 'network';
    // The Window Manager pane is greyed out on any other compositor, so a
    // route into it lands where a route naming nothing would.
    if (_selectedCategory == 'miracle' &&
        (MiracleScope.readOf(context)?.unsupported ?? false)) {
      _selectedCategory = 'network';
    }
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
          // Moved by dragging the tab strip; see [_moveBy].
          offset: _offset,
          // No backdrop-tap dismiss, deliberately: the settings panel is a
          // workspace, and a stray click on the scrim losing an in-progress
          // edit would be worse than needing Escape or the close button.
          foreground: _buildForeground,
          child: LayoutBuilder(
            // As the scaffold's child this is built once per surface-size
            // change, not on every animation frame.
            builder: (context, constraints) {
              final available = constraints.biggest;
              final size = overlayPanelSize(available);
              _maxOffset = Offset(
                math.max(0.0, (available.width - size.width) / 2),
                math.max(0.0, (available.height - size.height) / 2),
              );
              // Its own layer, so a drag moves a recorded picture instead of
              // re-recording a workspace of text on every pointer event.
              return RepaintBoundary(child: _buildPanel(theme, size));
            },
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
    if (tab == _selectedTab || !isOverviewTab(tab)) return;
    _setTab(tab);
    // The keyboard comes back to the panel's own listener, off whatever field
    // the tab being left had it in: a hidden tab is behind the IndexedStack's
    // `ExcludeFocus`, and Escape has to keep reaching somebody. A tab that
    // wants it — the board's search — takes it once it is shown.
    _focusNode.requestFocus();
    _panelEntry.markNeedsBuild();
  }

  /// Records [tab] as the visible one, here and in [SettingsOverlay.tab].
  void _setTab(String tab) {
    _selectedTab = tab;
    widget.tab?.value = tab;
  }

  /// The root wrote a tab into [SettingsOverlay.tab].
  void _onTabRequested() {
    final tab = widget.tab?.value;
    if (tab != null) _selectTab(tab);
  }

  /// A page of the Settings tab, from inside the overview — the todo board's
  /// "Open Accounts settings". In place, since the overview is already where
  /// that page is.
  void _openSettingsPage(SettingsRoute route) {
    _selectedCategory = route.category;
    if (_selectedTab != OverviewTab.settings) {
      _selectTab(OverviewTab.settings);
    } else {
      _panelEntry.markNeedsBuild();
    }
  }

  /// A drag on the tab strip, clamped so that the whole panel stays on screen.
  void _moveBy(Offset delta) {
    final next = _offset.value + delta;
    _offset.value = Offset(
      next.dx.clamp(-_maxOffset.dx, _maxOffset.dx),
      next.dy.clamp(-_maxOffset.dy, _maxOffset.dy),
    );
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
    _setTab(field.route.tab);
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
    widget.tab?.removeListener(_onTabRequested);
    _lastOffset = _offset.value;
    _offset.dispose();
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
      // editing keys instead of dropping them. Tab between fields is the other
      // half a WidgetsApp would have supplied.
      child: DefaultTextEditingShortcuts(
        child: TabFocusTraversal(
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
                  // A note's open menu is backed out of first, as the board
                  // backs out of its own.
                  if (_stickyNotes.currentState?.dismissMenu() ?? false) return;
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
                    _selectedTab == OverviewTab.settings) {
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
                onJump: _jumpToSetting,
                child: OpaquePopupScope(
                  child: Overlay(initialEntries: [_panelEntry]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The overview's corner actions — things done in the overview rather than
  /// on one of its tabs — and the sticky notes around the panel. The window's
  /// rather than the panel's, so they are on every tab: the buttons stay in
  /// the output's corner and the notes travel with the panel.
  List<OverviewAction> get _actions => [
    OverviewAction(
      icon: FontAwesomeIcons.noteSticky,
      label: 'New note',
      onTap: () => _stickyNotes.currentState?.addNote(),
    ),
  ];

  Widget _buildForeground(BuildContext context, Animation<double> opacity) {
    final actions = _actions;
    return Stack(
      children: [
        // Under the notes, so a note's menu barrier covers the buttons too.
        Positioned(
          left: kOverviewActionInset,
          top: kOverviewActionInset,
          child: FadeTransition(
            opacity: opacity,
            child: OverviewActionBar(actions: actions),
          ),
        ),
        Positioned.fill(
          child: StickyNoteLayer(
            key: _stickyNotes,
            offset: _offset,
            cardSizeFor: overlayPanelSize,
            opacity: opacity,
            reserved: [overviewActionBarRect(actions.length)],
            // The keyboard comes back to the panel's listener, so Escape
            // still closes the overview once a note has let go of it.
            onKeyboardReleased: _focusNode.requestFocus,
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(ThemeConfig theme, Size size) {
    _visited.add(_selectedTab);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: OverlayCard(
        color: overlayPanelFill(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: the tab bar, plus the close button — and the handle the
            // panel is moved by. A pan rather than a drag on press, so a click
            // on a tab is still a click: the tab's tap wins unless the pointer
            // travels past the slop first.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => _moveBy(details.delta),
              child: MouseRegion(
                // The tabs and the close button keep their own pointer cursor;
                // the strip between and beside them says it can be dragged.
                cursor: SystemMouseCursors.move,
                child: _buildHeader(theme),
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
            // latter drives the world clocks' one-second timer. A tab not yet
            // visited is not built at all; see [_visited].
            Expanded(
              child: IndexedStack(
                index: _tabs.indexWhere((t) => t.id == _selectedTab),
                sizing: StackFit.expand,
                children: [
                  for (final tab in _tabs)
                    if (_visited.contains(tab.id))
                      _buildTab(tab.id, theme)
                    else
                      const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tab strip and the close button.
  Widget _buildHeader(ThemeConfig theme) {
    return Container(
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
    );
  }

  Widget _buildTab(String tab, ThemeConfig theme) {
    final active = _selectedTab == tab;
    switch (tab) {
      case OverviewTab.calendar:
        return CalendarTab(active: active);
      case OverviewTab.system:
        return SystemTab(active: active);
      case OverviewTab.systemInfo:
        return const SystemInfoTab();
      case OverviewTab.settings:
        return _buildSettingsBody(theme);
      case OverviewTab.todo:
        return TodoBoard(
          // The overview's own: Escape with nothing left on the board to back
          // out of closes the overview, and a date picker goes as it leaves.
          closingNotifier: widget.closingNotifier,
          active: active,
          onOpenAccounts: () => _openSettingsPage(SettingsRoute.accounts),
        );
      case OverviewTab.shortcuts:
        return const KeybindCheatsheet();
      default:
        return const SizedBox.shrink();
    }
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
                  SettingsSidebar(
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
      case 'power':
        return const PowerSettingsPage();
      case 'miracle':
        final miracle = MiracleScope.readOf(context);
        final page = MiracleSettingsPage(
          initialCategory: widget.route?.miracleCategory,
        );
        if (miracle == null) return page;
        // Only reachable when the compositor turned out not to be miracle
        // after the pane was opened — an i3-compatible socket that never
        // answered `GET_KEYBINDS`. The sidebar greys the row out from then on.
        return ListenableBuilder(
          listenable: miracle,
          builder: (context, child) =>
              miracle.unsupported ? const _NotMiraclePane() : child!,
          child: page,
        );
      case 'default_apps':
        return const DefaultAppsSettingsPage();
      case 'accounts':
        return const AccountsSettingsPage();
      case 'shell':
        return ShellSettingsPage(
          initialCategory: widget.route?.shellCategory,
          initialModule: widget.route?.module,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

/// The settings tab's category list. Public for the tests alone: the overlay
/// around it cannot be pumped without the whole shell's stores.
@visibleForTesting
class SettingsSidebar extends StatelessWidget {
  const SettingsSidebar({
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    // The manager settles [MiracleManager.unsupported] once, but possibly after
    // the overlay has opened, so the sidebar listens for it.
    final miracle = MiracleScope.maybeOf(context);
    if (miracle == null) return _build(notMiracle: false);
    return ListenableBuilder(
      listenable: miracle,
      builder: (context, _) => _build(notMiracle: miracle.unsupported),
    );
  }

  Widget _build({required bool notMiracle}) {
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
              icon: FontAwesomeIcons.gaugeHigh,
              label: 'Power',
              selected: selectedCategory == 'power',
              onTap: () => onCategorySelected('power'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.wandMagicSparkles,
              label: 'Window Manager',
              selected: selectedCategory == 'miracle',
              onTap: () => onCategorySelected('miracle'),
              disabledReason: notMiracle ? kWindowManagerUnavailable : null,
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.arrowUpRightFromSquare,
              label: 'Default Apps',
              selected: selectedCategory == 'default_apps',
              onTap: () => onCategorySelected('default_apps'),
            ),
            _SidebarItem(
              icon: FontAwesomeIcons.circleUser,
              label: 'Accounts',
              selected: selectedCategory == 'accounts',
              onTap: () => onCategorySelected('accounts'),
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

/// Why the Window Manager row is greyed out, shown when the pointer rests on it.
const String kWindowManagerUnavailable =
    '$kNotMiracleMessage These settings edit Miracle WM\'s own configuration, '
    'so they are only available in a Miracle WM session.';

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabledReason,
  });

  final FaIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Non-null greys the row out, makes it inert and shows this as a tooltip.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final enabled = disabledReason == null;
    final foregroundAlpha = enabled ? 0.8 : 0.35;
    return SettingsTooltip(
      message: disabledReason,
      child: HoverRegion(
        onTap: onTap,
        enabled: enabled,
        builder: (context, hovered) => _buildRow(
          theme,
          hovered: enabled && hovered,
          foregroundAlpha: foregroundAlpha,
        ),
      ),
    );
  }

  Widget _buildRow(
    ThemeConfig theme, {
    required bool hovered,
    required double foregroundAlpha,
  }) {
    final Color bg;
    if (selected) {
      bg = theme.accent.withValues(alpha: 0.25);
    } else if (hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = const Color(0x00000000);
    }
    final foreground = selected
        ? theme.accentText
        : theme.popupForeground.withValues(alpha: foregroundAlpha);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ShellRadii.control),
      ),
      child: Row(
        children: [
          FaIcon(icon, size: ShellFontSizes.body, color: foreground),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: foreground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the Window Manager pane shows if the compositor is found not to be
/// miracle-wm while the pane is open.
class _NotMiraclePane extends StatelessWidget {
  const _NotMiraclePane();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: SettingsHint(kWindowManagerUnavailable),
  );
}
