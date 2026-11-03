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

import 'package:flutter/widgets.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/shell/modules.dart'
    show moduleSettingsPageByKey;
import 'package:moonswing/overlay/settings/shell/panels.dart' show moduleTitle;
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
};

/// Every route [moduleMenuItems] can open, for the test that checks each one
/// lands on a real page.
@visibleForTesting
Iterable<SettingsRoute> get relatedModuleSettingsRoutes =>
    _kRelatedSettings.values.map((link) => link.$2);

/// The rows of [moduleKey]'s right-click menu: its quick settings, then the
/// pages that configure it, ending with the panel it sits in when [panelName]
/// is known.
///
/// [openSettings] opens a route — the region passes one that names the output
/// the bar is on. Every link closes the menu first.
List<DesktopMenuItem> moduleMenuItems({
  required String moduleKey,
  required String? panelName,
  required VoidCallback close,
  required void Function(SettingsRoute route) openSettings,
  ConfigStore? store,
  Module? module,
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

  final related = _kRelatedSettings[moduleKey];
  return [
    ...quick,
    if (quick.isNotEmpty) const DesktopMenuDivider(),
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
}

/// The rows of a bar's blank-space menu: the bar's own tab in Panels & Layout,
/// and the settings overlay's landing page, which a right-click on blank space
/// always offers.
List<DesktopMenuItem> panelMenuItems({
  required String panelName,
  required VoidCallback close,
  required void Function(SettingsRoute route) openSettings,
}) {
  void go(SettingsRoute route) {
    close();
    openSettings(route);
  }

  return [
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
  });

  final String moduleKey;
  final String? panelName;

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

/// Wraps one module of a bar: a right-click anywhere in its box opens its
/// menu, anchored under it like the module's own popups.
class ModuleMenuRegion extends StatefulWidget {
  const ModuleMenuRegion({
    super.key,
    required this.moduleKey,
    required this.panelName,
    required this.child,
    this.debugOnMenu,
  });

  final String moduleKey;

  /// The `[panels.<name>]` the module sits in, for "Panel settings…".
  final String? panelName;

  final Widget child;

  /// Called instead of opening the menu, for a test with no layer-shell
  /// window to open a popup from.
  @visibleForTesting
  final VoidCallback? debugOnMenu;

  @override
  State<ModuleMenuRegion> createState() => _ModuleMenuRegionState();
}

class _ModuleMenuRegionState extends State<ModuleMenuRegion>
    with PopupHost<ModuleMenuRegion> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _open() {
    if (widget.debugOnMenu case final onMenu?) return onMenu();
    // The right-click's own pointer-down has already asked the coordinator to
    // dismiss what was open, this menu included; the post-frame hop is the
    // dock's, for the dock's reason (see `_openUnpinMenu`).
    if (isPopupOpen) {
      closePopup();
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
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
    return ModuleMenuScope(
      moduleKey: widget.moduleKey,
      panelName: widget.panelName,
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
    with PopupHost<PanelMenuRegion> {
  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _open(TapUpDetails details) {
    final at = details.globalPosition;
    if (widget.debugOnMenu case final onMenu?) return onMenu(at);
    if (isPopupOpen) {
      closePopup();
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(at));
    } else {
      _show(at);
    }
  }

  void _show(Offset at) {
    if (!mounted) return;
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
