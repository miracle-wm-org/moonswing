import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xdg_icons/xdg_icons.dart';

import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/dbus_menu.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/status_notifier_service.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

/// Configuration for the system tray module (`[modules.system_tray]`).
class SystemTrayConfig {
  const SystemTrayConfig({
    this.iconSize = 16,
    this.collapsedOverlap = 10,
    this.expandedSpacing = 6,
    this.hiddenItems = const [],
  });

  /// Rendered width/height of each tray icon, in logical pixels.
  final double iconSize;

  /// How far each icon overlaps its neighbour when the tray is at rest.
  final double collapsedOverlap;

  /// Gap between icons when the tray is hovered and spread apart.
  final double expandedSpacing;

  /// SNI `Id` or `Title` values to hide from the tray.
  final List<String> hiddenItems;

  factory SystemTrayConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SystemTrayConfig();
    return SystemTrayConfig(
      iconSize: map.doubleOr('icon_size', 16),
      collapsedOverlap: map.doubleOr('collapsed_overlap', 10),
      expandedSpacing: map.doubleOr('expanded_spacing', 6),
      hiddenItems: map.stringListOr('hidden_items'),
    );
  }
}

class SystemTrayModule extends Module {
  SystemTrayConfig _config = const SystemTrayConfig();

  @override
  String get configKey => 'system_tray';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = SystemTrayConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (_) => SystemTray(config: _config);
}

/// Panel widget that renders the registered StatusNotifierItem icons.
///
/// Icons overlap in a condensed strip at rest and spread apart with comfortable
/// spacing while the strip is hovered, so each becomes individually clickable.
class SystemTray extends StatefulWidget {
  const SystemTray({super.key, required this.config});

  final SystemTrayConfig config;

  @override
  State<SystemTray> createState() => _SystemTrayState();
}

class _SystemTrayState extends State<SystemTray> with PopupHost<SystemTray> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    TrayStore.instance.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    TrayStore.instance.removeListener(_onStoreChanged);
    closePopup();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  bool _isHidden(TrayItem item) {
    final hidden = widget.config.hiddenItems;
    if (hidden.isEmpty) return false;
    return hidden.contains(item.id) || hidden.contains(item.title);
  }

  Future<void> _openItemMenu(BuildContext iconContext, TrayItem item) async {
    // Toggle: a second click (on any icon) dismisses the open menu.
    if (isPopupOpen) {
      closePopup();
      return;
    }
    final root = item.menuPath != null ? await fetchTrayMenu(item) : null;
    if (!mounted) return;
    if (root == null || root.children.every((c) => !c.visible)) {
      // No usable menu — fall back to activating the item.
      await activateTrayItem(item);
      return;
    }
    // The icon may have been removed from the tray during the async fetch.
    if (!iconContext.mounted) return;
    openBarPopup(
      iconContext,
      // One State serves the whole strip, so the reopen guard has to be keyed
      // per icon: clicking a *different* icon while a menu is open must open
      // that icon's menu, not be read as re-clicking the one just dismissed.
      ownerKey: (this, item.id),
      preferredConstraints: const BoxConstraints(
        minWidth: 160,
        maxWidth: 320,
        minHeight: 24,
        maxHeight: 600,
      ),
      child: ThemeProvider(
        child: PopupBounceIn(
          child: _TrayMenu(
            item: item,
            root: root,
            onClose: closePopup,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items =
        TrayStore.instance.items.where((i) => !_isHidden(i)).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final size = widget.config.iconSize;
    final step = _hovered
        ? size + widget.config.expandedSpacing
        : size - widget.config.collapsedOverlap;
    final totalWidth = (items.length - 1) * step + size;

    // Earlier icons paint on top for a clean left-to-right cascade; keys keep
    // each icon's animation state stable as items come and go.
    final children = <Widget>[
      for (var i = 0; i < items.length; i++)
        AnimatedPositioned(
          key: ValueKey(items[i].busName),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: i * step,
          top: 0,
          width: size,
          height: size,
          child: _TrayIconButton(
            item: items[i],
            size: size,
            onPressed: (ctx) => _openItemMenu(ctx, items[i]),
          ),
        ),
    ].reversed.toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: totalWidth,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// A single hover-highlighted, tappable tray icon.
class _TrayIconButton extends StatefulWidget {
  const _TrayIconButton({
    required this.item,
    required this.size,
    required this.onPressed,
  });

  final TrayItem item;
  final double size;
  final void Function(BuildContext iconContext) onPressed;

  @override
  State<_TrayIconButton> createState() => _TrayIconButtonState();
}

class _TrayIconButtonState extends State<_TrayIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => widget.onPressed(context),
        child: Container(
          decoration: BoxDecoration(
            // The one hover in the shell that used to ignore the theme.
            color: _hovered
                ? ThemeScope.of(context).surfaceHover.withValues(alpha: 0.16)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: _TrayIcon(
            item: widget.item,
            size: widget.size,
            foreground: theme.foreground,
          ),
        ),
      ),
    );
  }
}

/// Renders a tray item's icon: a raw pixmap when provided, otherwise a themed
/// icon name, otherwise a monochrome fallback glyph.
class _TrayIcon extends StatefulWidget {
  const _TrayIcon({
    required this.item,
    required this.size,
    required this.foreground,
  });

  final TrayItem item;
  final double size;
  final Color foreground;

  @override
  State<_TrayIcon> createState() => _TrayIconState();
}

class _TrayIconState extends State<_TrayIcon> {
  ui.Image? _decoded;
  TrayIconPixmap? _decodedFrom;

  @override
  void initState() {
    super.initState();
    _maybeDecode();
  }

  @override
  void didUpdateWidget(_TrayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeDecode();
  }

  void _maybeDecode() {
    final pixmap = widget.item.iconPixmap;
    if (pixmap == null) {
      if (_decoded != null) {
        _decoded!.dispose();
        _decoded = null;
        _decodedFrom = null;
      }
      return;
    }
    if (identical(pixmap, _decodedFrom)) return;
    _decodedFrom = pixmap;
    _decodePixmap(pixmap);
  }

  Future<void> _decodePixmap(TrayIconPixmap pixmap) async {
    // SNI pixmaps are ARGB32 in network byte order (per pixel: A, R, G, B).
    // Reorder to RGBA8888 for ui.decodeImageFromPixels.
    final src = pixmap.bytes;
    final pixelCount = pixmap.width * pixmap.height;
    final rgba = Uint8List(pixelCount * 4);
    for (var i = 0; i < pixelCount; i++) {
      final o = i * 4;
      final a = src[o];
      final r = src[o + 1];
      final g = src[o + 2];
      final b = src[o + 3];
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = a;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      pixmap.width,
      pixmap.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    if (!mounted || !identical(widget.item.iconPixmap, pixmap)) {
      image.dispose();
      return;
    }
    setState(() {
      _decoded?.dispose();
      _decoded = image;
    });
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Widget _fallback() {
    final label = widget.item.title.isNotEmpty
        ? widget.item.title
        : widget.item.id;
    if (label.isEmpty) {
      return FaIcon(FontAwesomeIcons.circleDot,
          size: widget.size * 0.8, color: widget.foreground);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Text(
          label[0].toUpperCase(),
          style: TextStyle(fontSize: widget.size * 0.6, color: widget.foreground),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item.iconPixmap != null) {
      final image = _decoded;
      if (image == null) {
        return SizedBox(width: widget.size, height: widget.size);
      }
      return RawImage(
        image: image,
        width: widget.size,
        height: widget.size,
        filterQuality: FilterQuality.medium,
      );
    }
    if (item.iconName.startsWith('/')) {
      return Image.file(
        File(item.iconName),
        width: widget.size,
        height: widget.size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (item.iconName.isNotEmpty) {
      return XdgIcon(
        name: item.iconName,
        size: widget.size.round(),
        iconNotFoundBuilder: _fallback,
      );
    }
    return _fallback();
  }
}

/// Popup content: the item's dbusmenu rendered as a tappable list. Submenus
/// expand inline when tapped.
class _TrayMenu extends StatefulWidget {
  const _TrayMenu({
    required this.item,
    required this.root,
    required this.onClose,
  });

  final TrayItem item;
  final MenuNode root;
  final VoidCallback onClose;

  @override
  State<_TrayMenu> createState() => _TrayMenuState();
}

class _TrayMenuState extends State<_TrayMenu> {
  final Set<int> _expanded = {};

  void _onLeafTap(MenuNode node) {
    sendTrayMenuClick(widget.item, node.id);
    widget.onClose();
  }

  List<Widget> _buildRows(List<MenuNode> nodes, int depth) {
    final rows = <Widget>[];
    for (final node in nodes) {
      if (!node.visible) continue;
      if (node.isSeparator) {
        rows.add(const _MenuSeparator());
        continue;
      }
      final expanded = _expanded.contains(node.id);
      rows.add(_MenuRow(
        node: node,
        depth: depth,
        expanded: expanded,
        onTap: () {
          if (node.hasSubmenu) {
            setState(() {
              if (expanded) {
                _expanded.remove(node.id);
              } else {
                _expanded.add(node.id);
              }
            });
          } else if (node.enabled) {
            _onLeafTap(node);
          }
        },
      ));
      if (node.hasSubmenu && expanded) {
        rows.addAll(_buildRows(node.children, depth + 1));
      }
    }
    return rows;
  }

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
        child: PopupCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildRows(widget.root.children, 0),
          ),
        ),
      ),
    );
  }
}

class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: theme.divider,
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.onTap,
  });

  final MenuNode node;
  final int depth;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final node = widget.node;
    final enabled = node.enabled || node.hasSubmenu;
    final color = enabled ? theme.popupForeground : theme.muted;

    Widget? leading;
    if (node.toggleType.isNotEmpty) {
      leading = FaIcon(
        node.toggleType == 'radio'
            ? (node.toggleState == 1
                ? FontAwesomeIcons.solidCircleDot
                : FontAwesomeIcons.circle)
            : (node.toggleState == 1
                ? FontAwesomeIcons.squareCheck
                : FontAwesomeIcons.square),
        size: 12,
        color: color,
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: _hovered && enabled ? theme.surfaceHover : null,
          padding: EdgeInsets.only(
            left: 12.0 + widget.depth * 14.0,
            right: 12,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  node.label.isEmpty ? ' ' : node.label,
                  style: TextStyle(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (node.hasSubmenu)
                FaIcon(
                  widget.expanded
                      ? FontAwesomeIcons.chevronDown
                      : FontAwesomeIcons.chevronRight,
                  size: 10,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
