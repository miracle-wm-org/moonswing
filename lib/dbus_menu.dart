import 'package:dbus/dbus.dart';

/// Client for the `com.canonical.dbusmenu` protocol used by StatusNotifierItem
/// tray icons to expose their context menu.
///
/// A tray item advertises a menu object path via its `Menu` property; this class
/// fetches the layout as a [MenuNode] tree and reports clicks back. The recursive
/// `GetLayout` result has signature `(ia{sv}av)` — id, properties, children.
const String dbusMenuInterface = 'com.canonical.dbusmenu';

/// A single node in a dbusmenu tree.
///
/// The root node (id 0) is a container whose [children] are the top-level
/// entries. Leaf nodes are clickable; nodes with a non-empty [children] list are
/// submenus; nodes whose type is `separator` render as a divider.
class MenuNode {
  MenuNode({
    required this.id,
    required this.label,
    required this.type,
    required this.enabled,
    required this.visible,
    required this.toggleType,
    required this.toggleState,
    required this.children,
  });

  /// dbusmenu item id, passed back in `Event` when clicked.
  final int id;

  /// Display label with the `_` mnemonic markers stripped.
  final String label;

  /// `standard` (default) or `separator`.
  final String type;

  final bool enabled;
  final bool visible;

  /// `checkmark`, `radio`, or empty for a plain item.
  final String toggleType;

  /// 1 = on, 0 = off, -1 = indeterminate/not-toggleable.
  final int toggleState;

  final List<MenuNode> children;

  bool get isSeparator => type == 'separator';
  bool get hasSubmenu => children.isNotEmpty;

  static MenuNode _fromLayout(DBusValue layout) {
    // layout is a struct (ia{sv}av): id, properties, children.
    final parts = layout.asStruct();
    final id = parts[0].asInt32();
    final props = parts[1].asStringVariantDict();
    final childrenVariants = parts[2].asArray();

    String stringProp(String key, [String fallback = '']) =>
        props.containsKey(key) ? props[key]!.asString() : fallback;
    bool boolProp(String key, bool fallback) =>
        props.containsKey(key) ? props[key]!.asBoolean() : fallback;

    // 'label' carries `_` accelerator markers; drop them for display.
    final rawLabel = stringProp('label');
    final label = rawLabel.replaceAll('_', '');

    final children = <MenuNode>[];
    for (final child in childrenVariants) {
      // Each child is a variant wrapping the (ia{sv}av) struct.
      children.add(_fromLayout(child.asVariant()));
    }

    return MenuNode(
      id: id,
      label: label,
      type: stringProp('type', 'standard'),
      enabled: boolProp('enabled', true),
      visible: boolProp('visible', true),
      toggleType: stringProp('toggle-type'),
      toggleState:
          props.containsKey('toggle-state') ? props['toggle-state']!.asInt32() : -1,
      children: children,
    );
  }
}

/// Wraps a remote `com.canonical.dbusmenu` object for one tray item.
class DBusMenuClient {
  DBusMenuClient(DBusClient client,
      {required String busName, required DBusObjectPath path})
      : _object = DBusRemoteObject(client, name: busName, path: path);

  final DBusRemoteObject _object;

  /// Notifies the application the menu is about to be shown (letting apps that
  /// populate menus lazily fill them in), then fetches and parses the layout.
  ///
  /// Returns the root [MenuNode] (id 0), or null if the menu could not be
  /// retrieved.
  Future<MenuNode?> fetchLayout() async {
    try {
      // AboutToShow(0) — root id. Ignore failures; some apps don't implement it.
      try {
        await _object.callMethod(
          dbusMenuInterface,
          'AboutToShow',
          [const DBusInt32(0)],
          replySignature: DBusSignature('b'),
        );
      } catch (_) {}

      // GetLayout(parentId=0, recursionDepth=-1, propertyNames=[]) -> (u(ia{sv}av))
      final result = await _object.callMethod(
        dbusMenuInterface,
        'GetLayout',
        [
          const DBusInt32(0),
          const DBusInt32(-1),
          DBusArray.string(const []),
        ],
        replySignature: DBusSignature('u(ia{sv}av)'),
      );
      // returnValues[0] = revision (u), returnValues[1] = layout struct.
      return MenuNode._fromLayout(result.returnValues[1]);
    } catch (_) {
      return null;
    }
  }

  /// Reports that the menu entry [id] was clicked. `data` is an empty variant
  /// and the timestamp is best-effort (0 is accepted by every implementation).
  Future<void> clickItem(int id) async {
    try {
      await _object.callMethod(
        dbusMenuInterface,
        'Event',
        [
          DBusInt32(id),
          const DBusString('clicked'),
          const DBusVariant(DBusString('')),
          const DBusUint32(0),
        ],
        replySignature: DBusSignature(''),
        noReplyExpected: true,
      );
    } catch (_) {
      // Item may have vanished; nothing actionable.
    }
  }
}
