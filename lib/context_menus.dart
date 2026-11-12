// The right-click menus of the bars: one on every module, one on a bar's blank
// space — and the quick-setting rows those and the desktop widget menu share.
//
// A module's menu is its quick settings, then the way to the settings page that
// configures it and to the panel it sits in. Nothing about it is the module's
// own code: the rows come off the module's settings page (the rows flagged
// `quick:` in `overlay/settings/shell/modules.dart`) plus whatever the module
// alone can answer (`Module.quickSettings`), so a new module gets a menu by
// existing and a new option reaches it by being flagged.
//
// **The deeper right-click wins.** These regions listen with a secondary *tap*
// recognizer, and answer on its tap-up, which only the arena's winner sees. A
// module with a right-click of its own — the dock's unpin menu, a workspace's
// placement menu — is a deeper recognizer on the same pointer and wins the
// sweep, so the two never open together; those two append this menu's rows to
// their own instead, through [ModuleMenuScope]. The bar's blank-space region is
// shallower than every module's, so it answers only where no module is.
//
// **Both menus edit the bar they were opened on.** A module's ends with taking
// it out of the bar and adding another beside it; the bar's blank space adds
// one to the section — left, centre or right, read as thirds of the bar — that
// was right-clicked. The modules on offer are a second popup rather than a
// page of the first, because a popup is sized once, as it opens; the edits are
// `panel_layout_edit.dart`'s, written straight to the config the bar follows.

import 'package:flutter/widgets.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/shell/modules.dart'
    show moduleSettingsPageByKey;
import 'package:moonswing/overlay/settings/shell/panels.dart'
    show moduleGlyph, moduleTitle;
import 'package:moonswing/panel_layout_edit.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/quick_settings.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_provider.dart';

/// The shared store, or null before `ConfigStore.initShared` — which is every
/// widget test that pumps a bar. A config-backed quick setting is then left
/// out rather than throwing out of a right-click.
ConfigStore? _sharedStore() {
  try {
    return ConfigStore.instance;
  } on StateError {
    return null;
  }
}

/// [settings] as menu rows.
///
/// Config-backed rows read and write [store] and follow it while the menu is
/// open, so flipping one shows at once — and so does one flipped from the
/// settings page underneath. They are left out when [store] is null. An action
/// row closes the menu (through [close]) *before* running, because what it does
/// may rebuild the surface the menu was opened from.
List<DesktopMenuItem> quickSettingItems(
  List<QuickSetting> settings, {
  required ConfigStore? store,
  required VoidCallback close,
}) {
  final items = <DesktopMenuItem>[];
  for (final setting in settings) {
    switch (setting) {
      case QuickToggle(:final label, :final path, :final defaultValue):
        if (store == null) continue;
        items.add(
          DesktopMenuLive(
            listenable: store,
            build: () {
              final on = store.get<bool>(path) ?? defaultValue;
              return [
                DesktopMenuEntry(
                  label: label,
                  checked: on,
                  onTap: () => store.set(path, !on),
                ),
              ];
            },
          ),
        );
      case final QuickChoice choice:
        if (store == null) continue;
        items
          ..add(DesktopMenuHeading(choice.label))
          ..add(
            DesktopMenuLive(
              listenable: store,
              build: () {
                final value =
                    store.get<String>(choice.path) ?? choice.defaultValue;
                return [
                  for (final option in choice.options)
                    DesktopMenuEntry(
                      label: choice.optionLabel(option),
                      selected: value == option,
                      selectable: true,
                      onTap: () => store.set(choice.path, option),
                    ),
                ];
              },
            ),
          );
      case final QuickAction action when action.isSwitch:
        // A switch whose state only its own tap moves is still redrawn after
        // the tap: the bump is what says so.
        final bump = _Bump();
        final listenable = action.listenable == null
            ? bump
            : Listenable.merge([action.listenable, bump]);
        items.add(
          DesktopMenuLive(
            listenable: listenable,
            build: () => [
              DesktopMenuEntry(
                label: action.label,
                icon: action.icon,
                checked: action.checked!(),
                onTap: () {
                  action.onTap();
                  bump.fire();
                },
              ),
            ],
          ),
        );
      case final QuickAction action:
        items.add(
          DesktopMenuEntry(
            label: action.label,
            icon: action.icon,
            onTap: () {
              close();
              action.onTap();
            },
          ),
        );
    }
  }
  return items;
}

class _Bump extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Settings pages that configure a module but are not its page under Shell ›
/// Modules — the machine's own settings a module is a view of. A module with
/// both offers both.
final Map<String, (String, SettingsRoute)> _kRelatedSettings = {
  'sound_control': ('Sound settings…', const SettingsRoute(category: 'audio')),
  'brightness': ('Display settings…', const SettingsRoute(category: 'display')),
  'keyboard_layout': ('Keyboard settings…', SettingsRoute.keyboard),
  'battery': ('Power settings…', SettingsRoute.power),
  'network': ('Network settings…', const SettingsRoute(category: 'network')),
  'system': (
    'Power button settings…',
    const SettingsRoute(shellCategory: 'Power Button'),
  ),
  'github': ('Accounts…', SettingsRoute.accounts),
  'quick_settings': ('Settings…', SettingsRoute.tab(OverviewTab.settings)),
};

/// Every route [moduleMenuItems] can open, for the test that checks each one
/// lands on a real page.
@visibleForTesting
Iterable<SettingsRoute> get relatedModuleSettingsRoutes =>
    _kRelatedSettings.values.map((link) => link.$2);

/// The rows of [moduleKey]'s right-click menu: its quick settings, then the
/// pages that configure it, ending with the panel it sits in when [panelName]
/// is known — and then the bar's own edits: [onAddModule] ("Add module…",
/// beside this one) and [onRemove] ("Remove from panel"), each left out when
/// null.
///
/// [openSettings] opens a route — the region passes one that names the output
/// the bar is on. Every link and edit closes the menu first.
List<DesktopMenuItem> moduleMenuItems({
  required String moduleKey,
  required String? panelName,
  required VoidCallback close,
  required void Function(SettingsRoute route) openSettings,
  ConfigStore? store,
  Module? module,
  VoidCallback? onAddModule,
  VoidCallback? onRemove,
}) {
  final page = moduleSettingsPageByKey(moduleKey);
  final quick = quickSettingItems(
    [
      ...?(module ?? Module.lookup(moduleKey))?.quickSettings,
      ...?page?.quickSettings,
    ],
    store: store,
    close: close,
  );
  void go(SettingsRoute route) {
    close();
    openSettings(route);
  }

  void act(VoidCallback action) {
    close();
    action();
  }

  final related = _kRelatedSettings[moduleKey];
  final links = [
    if (page != null)
      DesktopMenuEntry(
        label: '${page.title} settings…',
        icon: ShellGlyph.settings,
        onTap: () => go(page.route),
      ),
    if (related != null)
      DesktopMenuEntry(
        label: related.$1,
        icon: ShellGlyph.sliders,
        onTap: () => go(related.$2),
      ),
    if (panelName != null)
      DesktopMenuEntry(
        label: 'Panel settings…',
        icon: ShellGlyph.columns,
        onTap: () => go(SettingsRoute.panel(panelName)),
      ),
  ];
  final edits = [
    if (onAddModule != null)
      DesktopMenuEntry(
        label: 'Add module…',
        icon: ShellGlyph.add,
        onTap: () => act(onAddModule),
      ),
    if (onRemove != null)
      DesktopMenuEntry(
        label: 'Remove from panel',
        icon: ShellGlyph.trash,
        onTap: () => act(onRemove),
      ),
  ];
  return [
    ...quick,
    if (quick.isNotEmpty && links.isNotEmpty) const DesktopMenuDivider(),
    ...links,
    if ((quick.isNotEmpty || links.isNotEmpty) && edits.isNotEmpty)
      const DesktopMenuDivider(),
    ...edits,
  ];
}

/// The rows of a bar's blank-space menu: adding a module to the section that
/// was right-clicked, named by [slotLabel], when [onAddModule] is given; then
/// the bar's own tab in Panels & Layout, and the settings overlay's landing
/// page, which a right-click on blank space always offers.
List<DesktopMenuItem> panelMenuItems({
  required String panelName,
  required VoidCallback close,
  required void Function(SettingsRoute route) openSettings,
  String? slotLabel,
  VoidCallback? onAddModule,
}) {
  void go(SettingsRoute route) {
    close();
    openSettings(route);
  }

  return [
    if (onAddModule != null) ...[
      DesktopMenuEntry(
        label: slotLabel == null
            ? 'Add module…'
            : 'Add module to ${slotLabel.toLowerCase()}…',
        icon: ShellGlyph.add,
        onTap: () {
          close();
          onAddModule();
        },
      ),
      const DesktopMenuDivider(),
    ],
    DesktopMenuEntry(
      label: 'Panel settings…',
      icon: ShellGlyph.columns,
      onTap: () => go(SettingsRoute.panel(panelName)),
    ),
    DesktopMenuEntry(
      label: 'Settings…',
      icon: ShellGlyph.settings,
      onTap: () => go(const SettingsRoute()),
    ),
  ];
}

/// The rows of the "Add module" menu: one per module in [keys], by its title
/// and glyph, each closing the menu and then handing its key to [onPick] —
/// or one disabled row saying there is nothing left to add.
List<DesktopMenuItem> addModuleMenuItems({
  required List<String> keys,
  required VoidCallback close,
  required void Function(String key) onPick,
}) {
  if (keys.isEmpty) {
    return [
      DesktopMenuEntry(
        label: 'Every module is already on this panel',
        enabled: false,
        onTap: () {},
      ),
    ];
  }
  return [
    for (final key in keys)
      DesktopMenuEntry(
        label: moduleTitle(key),
        icon: moduleGlyph(key),
        onTap: () {
          close();
          onPick(key);
        },
      ),
  ];
}

/// "Top panel" for `top`; the name is the `[panels.<name>]` key.
String panelMenuTitle(String name) => name.isEmpty
    ? 'Panel'
    : '${name[0].toUpperCase()}${name.substring(1)} panel';

/// Opens the settings overlay on the output [context]'s bar is on.
///
/// The output is read *now*, as the menu opens, and the closure holds the
/// answer: a link runs after the menu has closed, by which time the element
/// that opened it may be gone — a quick setting that took its module out of
/// the bar, a monitor unplugged.
void Function(SettingsRoute route) _settingsOpenerFor(BuildContext context) {
  final output = DisplayScope.of(context)?.name;
  return (route) => SettingsController.instance.open(route, output);
}

/// Which module a subtree belongs to and which panel it sits in, for a module
/// whose own right-click menu wants to end with this module's rows.
class ModuleMenuScope extends InheritedWidget {
  const ModuleMenuScope({
    super.key,
    required this.moduleKey,
    required this.panelName,
    required super.child,
    this.onAddModule,
    this.onRemove,
  });

  final String moduleKey;
  final String? panelName;

  /// The bar's edits of this module's place, from its [ModuleMenuRegion]; null
  /// where the region cannot make them (no config store, no known place).
  final VoidCallback? onAddModule;
  final VoidCallback? onRemove;

  static ModuleMenuScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ModuleMenuScope>();

  /// The rows the module's own menu appends, behind a divider: everything
  /// [moduleMenuItems] offers. Read from the module's own [context], which is
  /// on the bar, at the moment its menu opens.
  static List<DesktopMenuItem> itemsFor(
    BuildContext context, {
    required VoidCallback close,
  }) {
    final scope = maybeOf(context);
    if (scope == null) return const [];
    return [
      const DesktopMenuDivider(),
      DesktopMenuHeading(moduleTitle(scope.moduleKey)),
      ...moduleMenuItems(
        moduleKey: scope.moduleKey,
        panelName: scope.panelName,
        close: close,
        openSettings: _settingsOpenerFor(context),
        store: _sharedStore(),
        onAddModule: scope.onAddModule,
        onRemove: scope.onRemove,
      ),
    ];
  }

  @override
  bool updateShouldNotify(ModuleMenuScope oldWidget) =>
      moduleKey != oldWidget.moduleKey || panelName != oldWidget.panelName;
}

/// What a context menu popup is offered: loose, so the card sizes to its rows.
const BoxConstraints _kMenuConstraints = BoxConstraints(
  maxWidth: 320,
  maxHeight: 560,
);

/// What both bar menus share: opening the "Add module" menu, as a popup of its
/// own once the menu that asked for it has gone.
mixin _AddModuleMenuHost<T extends StatefulWidget> on PopupHost<T> {
  /// Opens the modules [panel] could be given, adding the one picked to
  /// [slot] at [index] (its end when null). Under the pointer at [at], or
  /// under this host's own box.
  void showAddModuleMenu({
    required String panel,
    required String slot,
    required String header,
    int? index,
    Offset? at,
  }) {
    // The menu that offered this is closing; the hop is the dock's, as for a
    // right-click over an open menu.
    afterNextFrame(() {
      if (!mounted) return;
      final store = _sharedStore();
      if (store == null) return;
      final keys = addableModules(
        storedPanelLayout(store, panel),
        miracleUnsupported: MiracleScope.maybeOf(context)?.unsupported ?? false,
        titleOf: moduleTitle,
      );
      openBarPopup(
        context,
        at: at,
        preferredConstraints: _kMenuConstraints,
        child: ThemeProvider(
          child: DesktopMenuCard(
            header: header,
            scrollable: true,
            entries: addModuleMenuItems(
              keys: keys,
              close: closePopup,
              onPick: (key) => insertPanelModule(
                store,
                panel: panel,
                slot: slot,
                key: key,
                index: index,
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Wraps one module of a bar: a right-click anywhere in its box opens its
/// menu, anchored under it like the module's own popups.
class ModuleMenuRegion extends StatefulWidget {
  const ModuleMenuRegion({
    super.key,
    required this.moduleKey,
    required this.panelName,
    required this.child,
    this.slot,
    this.index,
    this.debugOnMenu,
  });

  final String moduleKey;

  /// The `[panels.<name>]` the module sits in, for "Panel settings…".
  final String? panelName;

  /// Where in [panelName]'s layout the module is — its section and its index
  /// in that section's list — for "Remove from panel" and "Add module…". Both
  /// rows are left out while either is unknown.
  final String? slot;
  final int? index;

  final Widget child;

  /// Called instead of opening the menu, for a test with no layer-shell
  /// window to open a popup from.
  @visibleForTesting
  final VoidCallback? debugOnMenu;

  @override
  State<ModuleMenuRegion> createState() => _ModuleMenuRegionState();
}

class _ModuleMenuRegionState extends State<ModuleMenuRegion>
    with PopupHost<ModuleMenuRegion>, _AddModuleMenuHost<ModuleMenuRegion> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  bool get _placed =>
      widget.panelName != null &&
      widget.slot != null &&
      widget.index != null &&
      _sharedStore() != null;

  /// Read off the widget when run, not when the menu opened: a menu row runs
  /// after the menu has closed.
  void _remove() {
    final store = _sharedStore();
    final panel = widget.panelName;
    final slot = widget.slot;
    final index = widget.index;
    if (store == null || panel == null || slot == null || index == null) {
      return;
    }
    removePanelModule(
      store,
      panel: panel,
      slot: slot,
      index: index,
      key: widget.moduleKey,
    );
  }

  void _addBeside() {
    final panel = widget.panelName;
    final slot = widget.slot;
    final index = widget.index;
    if (panel == null || slot == null || index == null) return;
    showAddModuleMenu(
      panel: panel,
      slot: slot,
      index: index + 1,
      header: 'Add module after ${moduleTitle(widget.moduleKey)}',
    );
  }

  void _open() {
    if (widget.debugOnMenu case final onMenu?) return onMenu();
    // The right-click's own pointer-down has already asked the coordinator to
    // dismiss what was open, this menu included; the post-frame hop is the
    // dock's, for the dock's reason (see `_openUnpinMenu`).
    if (isPopupOpen) {
      closePopup();
      afterNextFrame(_show);
    } else {
      _show();
    }
  }

  void _show() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final items = moduleMenuItems(
      moduleKey: widget.moduleKey,
      panelName: widget.panelName,
      close: closePopup,
      openSettings: _settingsOpenerFor(context),
      store: _sharedStore(),
      onAddModule: _placed ? _addBeside : null,
      onRemove: _placed ? _remove : null,
    );
    openBarPopup(
      context,
      preferredConstraints: _kMenuConstraints,
      // The card lays out under its own FlutterView, so it carries its own
      // theme — `ThemeScope` is an InheritedWidget and cannot span views.
      child: ThemeProvider(
        child: DesktopMenuCard(
          header: moduleTitle(widget.moduleKey),
          entries: items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placed = _placed;
    return ModuleMenuScope(
      moduleKey: widget.moduleKey,
      panelName: widget.panelName,
      onAddModule: placed ? _addBeside : null,
      onRemove: placed ? _remove : null,
      child: GestureDetector(
        // Opaque: a right-click on the module's padding, between its glyph and
        // its edge, is still a right-click on the module rather than on the
        // bar behind it.
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (_) => _open(),
        child: widget.child,
      ),
    );
  }
}

/// Wraps a bar's content: a right-click where no module is opens the bar's own
/// menu under the pointer.
class PanelMenuRegion extends StatefulWidget {
  const PanelMenuRegion({
    super.key,
    required this.panelName,
    required this.child,
    this.debugOnMenu,
  });

  final String panelName;
  final Widget child;

  /// Called with the pointer's position instead of opening the menu, for a
  /// test with no layer-shell window to open a popup from.
  @visibleForTesting
  final void Function(Offset at)? debugOnMenu;

  @override
  State<PanelMenuRegion> createState() => _PanelMenuRegionState();
}

class _PanelMenuRegionState extends State<PanelMenuRegion>
    with PopupHost<PanelMenuRegion>, _AddModuleMenuHost<PanelMenuRegion> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  /// The section a right-click at [local] is in: the bar read as thirds.
  String _slotAt(Offset local) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 'left';
    final vertical = BarScope.isVerticalOf(context);
    return panelSlotAt(
      vertical ? local.dy : local.dx,
      vertical ? box.size.height : box.size.width,
    );
  }

  void _open(TapUpDetails details) {
    final at = details.globalPosition;
    if (widget.debugOnMenu case final onMenu?) return onMenu(at);
    final slot = _slotAt(details.localPosition);
    if (isPopupOpen) {
      closePopup();
      afterNextFrame(() => _show(at, slot));
    } else {
      _show(at, slot);
    }
  }

  void _show(Offset at, String slot) {
    if (!mounted) return;
    final label = panelSlotLabel(
      slot,
      vertical: BarScope.isVerticalOf(context),
    );
    openBarPopup(
      context,
      at: at,
      preferredConstraints: _kMenuConstraints,
      child: ThemeProvider(
        child: DesktopMenuCard(
          header: panelMenuTitle(widget.panelName),
          entries: panelMenuItems(
            panelName: widget.panelName,
            close: closePopup,
            openSettings: _settingsOpenerFor(context),
            slotLabel: label,
            onAddModule: _sharedStore() == null
                ? null
                : () => showAddModuleMenu(
                    panel: widget.panelName,
                    slot: slot,
                    at: at,
                    header: 'Add module to ${label.toLowerCase()}',
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque, because the bar's blank space is exactly where nothing beneath
      // answers a hit: the `Align`s and `Padding` around the sections are
      // transparent to it.
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: _open,
      child: widget.child,
    );
  }
}
