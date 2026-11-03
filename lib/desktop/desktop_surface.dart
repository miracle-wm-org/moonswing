// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/background.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/context_menus.dart' show quickSettingItems;
import 'package:moonswing/desktop/desktop_actions.dart';
import 'package:moonswing/desktop/desktop_grid.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/desktop/desktop_store.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/overlay/settings/shell/modules.dart'
    show moduleSettingsPageByKey;
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/quick_settings.dart';
import 'package:moonswing/theme/theme_provider.dart';

/// What the background layer-shell window renders: the wallpaper, with the
/// desktop icon grid over it and the grid's context menus.
///
/// [background] is null in the grid-only case. That must render as *nothing*, not
/// as [BackgroundWindow]'s opaque empty fill, or a user with icons and no
/// wallpaper gets a black desktop instead of whatever their compositor draws.
class DesktopSurface extends StatefulWidget {
  const DesktopSurface({
    super.key,
    required this.background,
    required this.desktop,
    required this.store,
    this.panels = const {},
    this.onOpenSettings,
    this.onAddRequested,
    this.onKeyboardRequested,
  });

  final BackgroundConfig? background;
  final DesktopConfig desktop;
  final DesktopStore store;
  final Map<String, PanelConfig> panels;

  /// Opens the settings overlay at a route — "Change background…", "Settings…",
  /// a widget's own page — which only the root can do, so it arrives as a
  /// callback. Null hides every row that would call it.
  final void Function(SettingsRoute route)? onOpenSettings;

  /// "Add…" — the file picker cannot render from this surface (it would draw
  /// on the background layer, under every application window), so the root
  /// owns it and this asks for one. [applications] picks the `.desktop` filter.
  final void Function({required bool applications, required GridCell cell})?
      onAddRequested;

  /// Asks the root to give this surface keyboard focus for an in-place rename.
  /// Only the root owns the layer-shell controller that can change it.
  final void Function(bool wanted)? onKeyboardRequested;

  @override
  State<DesktopSurface> createState() => _DesktopSurfaceState();
}

class _DesktopSurfaceState extends State<DesktopSurface>
    with PopupHost<DesktopSurface> {
  /// The grid geometry the last build resolved, so a menu action (organize, or
  /// placing a new item) works against what the user is actually looking at.
  DesktopGridGeometry? _geometry;

  /// The "Open with…" candidates for the open menu.
  ///
  /// These carry live `GAppInfo*`s that this state owns — `appsForPath` is
  /// transfer-full and deliberately not served from `AppIndex`. Disposed when the
  /// popup closes and again in [dispose], because a popup dismissed by the
  /// compositor routes through `onClosed` but a shell teardown does not.
  List<AppEntry> _handlers = const [];

  @override
  void dispose() {
    _releaseHandlers();
    super.dispose();
  }

  void _releaseHandlers() {
    if (_handlers.isEmpty) return;
    disposeAppEntries(_handlers);
    _handlers = const [];
  }

  /// Opens a menu at [position] (surface-local).
  ///
  /// `openPopup` no-ops while one is open, so an already-open menu is closed first
  /// and the new one opened after the frame — the dance `modules/dock.dart` does.
  void _openMenu(Offset position, Widget child) {
    void open() {
      if (!mounted) return;
      openPopup(
        context,
        // A zero-size rect at the cursor: the menu's top-left goes there and
        // the compositor slides it to stay on-screen.
        anchorRect: position & Size.zero,
        parentAnchor: WindowPositionerAnchor.topLeft,
        childAnchor: WindowPositionerAnchor.topLeft,
        constraintAdjustment: kPopupSlide,
        // Loose, so the card sizes to its content.
        preferredConstraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        onClosed: _releaseHandlers,
        child: ThemeProvider(child: child),
      );
    }

    if (isPopupOpen) {
      closePopup();
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }

  void _onItemMenu(DesktopItem item, Offset position) {
    // Frozen here rather than read in the callbacks: the popup is a separate
    // surface and the selection could change under it, and a menu that said
    // "Remove 3 items" must not go on to remove some other number.
    final selected = Set<String>.of(widget.store.selectedTargets);
    final multiple = selected.length > 1;

    _openMenu(
      position,
      DesktopItemMenu(
        item: item,
        selectionCount: selected.length,
        handlers: () {
          _releaseHandlers();
          _handlers = openWithCandidates(item);
          return _handlers;
        },
        onOpen: () {
          closePopup();
          if (!multiple) {
            openDesktopItem(item);
            return;
          }
          for (final selection in widget.store.items) {
            if (selected.contains(selection.target)) {
              openDesktopItem(selection);
            }
          }
        },
        onOpenWith: (handler) {
          openDesktopItemWith(item, handler);
          closePopup();
        },
        onRename: () {
          closePopup();
          widget.store.beginRename(item.target);
        },
        onRemove: () {
          closePopup();
          // One commit for the whole selection, not one per icon.
          widget.store.removeItems(multiple ? selected : {item.target});
        },
      ),
    );
  }

  void _onEmptyMenu(GridCell cell, Offset position) {
    _openMenu(
      position,
      DesktopEmptyMenu(
        // The registry rather than a constructor parameter: the surface is the
        // shell, and this is where a compiled-in list is legitimately read. The
        // menu itself takes it as a parameter so it stays testable.
        widgetSpecs: DesktopWidgetRegistry.all,
        onAddApplication: () {
          closePopup();
          widget.onAddRequested?.call(applications: true, cell: cell);
        },
        onAddFile: () {
          closePopup();
          widget.onAddRequested?.call(applications: false, cell: cell);
        },
        onAddWidget: (spec) {
          closePopup();
          final geometry = _geometry;
          if (geometry == null) return;
          // Placed where the user right-clicked, or as near as the grid allows;
          // icons underneath are displaced by the store in the same commit.
          widget.store.addWidget(
            newWidgetItem(spec, cell, widget.store.widgets),
            geometry,
          );
        },
        onOrganize: () {
          closePopup();
          final geometry = _geometry;
          if (geometry != null) widget.store.organize(geometry);
        },
        onChangeBackground: () => _goToSettings(SettingsRoute.background),
        onOpenDesktopSettings: widget.onOpenSettings == null
            ? null
            : () => _goToSettings(SettingsRoute.desktop),
        onOpenSettings: widget.onOpenSettings == null
            ? null
            : () => _goToSettings(const SettingsRoute()),
      ),
    );
  }

  /// Closes the open menu and asks the root for the settings overlay at
  /// [route].
  void _goToSettings(SettingsRoute route) {
    closePopup();
    widget.onOpenSettings?.call(route);
  }

  /// A right-click on the wallpaper of an output with the grid switched off:
  /// there is nothing to add or arrange, but bare background still reaches
  /// Settings.
  void _onBackgroundMenu(TapDownDetails details) {
    if (widget.onOpenSettings == null) return;
    _openMenu(
      details.localPosition,
      DesktopBackgroundMenu(
        onChangeBackground: () => _goToSettings(SettingsRoute.background),
        onOpenSettings: () => _goToSettings(const SettingsRoute()),
      ),
    );
  }

  /// The shared store, or null before `ConfigStore.initShared` — a widget test.
  static ConfigStore? _store() {
    try {
      return ConfigStore.instance;
    } on StateError {
      return null;
    }
  }

  void _onWidgetMenu(DesktopWidgetItem item, Offset position) {
    final spec = DesktopWidgetRegistry.lookup(item.type);
    // The page that configures the widget: its spec's, or the desktop grid's,
    // where every widget is added and laid out. A widget configured by a
    // module's page — the weather card by the weather module's — may offer
    // that page's quick rows too.
    final route = spec?.settings ?? SettingsRoute.desktop;
    final page = spec?.offersPageQuickSettings ?? false
        ? moduleSettingsPageByKey(route.module)
        : null;
    final quick = <QuickSetting>[
      ...?spec?.quickSettings?.call(),
      ...?page?.quickSettings,
    ];
    final onOpenSettings = widget.onOpenSettings;
    _openMenu(
      position,
      DesktopWidgetMenu(
        item: item,
        spec: spec,
        quickSettings: quickSettingItems(
          quick,
          store: _store(),
          close: closePopup,
        ),
        settingsLabel: spec?.settings == null
            ? 'Desktop settings…'
            : '${spec!.name} settings…',
        onOpenWidgetSettings: onOpenSettings == null
            ? null
            : () => _goToSettings(route),
        onResetSize: spec == null
            ? null
            : () {
                closePopup();
                final geometry = _geometry;
                if (geometry == null) return;
                widget.store.resizeWidget(
                  item.id,
                  (
                    column: item.column,
                    row: item.row,
                    columnSpan: spec.defaultSpan.columns,
                    rowSpan: spec.defaultSpan.rows,
                  ),
                  geometry,
                  minSpan: spec.minSpan,
                  maxSpan: spec.maxSpan,
                );
              },
        onRemove: () {
          closePopup();
          widget.store.removeWidget(item.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Its own layer. The wallpaper is the most expensive single draw on this
          // surface — a full-output image resampled to fit — and it changes once
          // every few minutes at most, while the grid over it changes under the
          // pointer. Without a boundary every hover, band move and drag
          // re-records that scale into the surface's one picture.
          if (widget.background != null)
            // With the grid off nothing else on this surface answers a
            // right-click, so the wallpaper does. With it on, the grid's own
            // empty-space menu is the one, and this listens to nothing.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown:
                  widget.desktop.enabled ? null : _onBackgroundMenu,
              child: RepaintBoundary(
                child: BackgroundWindow(config: widget.background!),
              ),
            )
          else
            const SizedBox.expand(),
          // No ListenableBuilder here: DesktopLayer subscribes to the store
          // itself, because it also has to re-resolve GAppInfo pointers when
          // the item set changes, and doing that in a builder would leak.
          if (widget.desktop.enabled)
            DesktopLayer(
              store: widget.store,
              panels: widget.panels,
              onItemMenu: _onItemMenu,
              onWidgetMenu: _onWidgetMenu,
              onEmptyMenu: _onEmptyMenu,
              onGeometry: (geometry) => _geometry = geometry,
              onKeyboardRequested: widget.onKeyboardRequested,
            ),
        ],
      ),
    );
  }
}
