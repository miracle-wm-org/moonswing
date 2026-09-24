import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xdg_icons/xdg_icons.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_actions.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// One cell of the desktop grid: an icon over its label, with the selection
/// chrome.
///
/// Takes its resolved [AppEntry] as a parameter rather than looking one up.
/// `loadAppByPath` **refs** what it returns, so resolving per-build would leak a
/// `GAppInfo` every frame — the grid resolves once and disposes on change.
class DesktopIconTile extends StatelessWidget {
  const DesktopIconTile({
    super.key,
    required this.item,
    required this.iconSize,
    required this.showLabel,
    this.resolved,
    this.iconName = '',
    this.selected = false,
    this.hovered = false,
    this.missing = false,
  });

  final DesktopItem item;
  final double iconSize;
  final bool showLabel;

  /// The desktop entry behind an `app` item, when it resolved.
  final AppEntry? resolved;

  /// The themed icon name, resolved once by the grid. Empty falls back to a
  /// font glyph.
  final String iconName;

  final bool selected;
  final bool hovered;

  /// Whether the target no longer exists. Drawn dimmed rather than removed —
  /// an offline network mount must not cost the user their arrangement.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final label = labelForItem(item, resolved: resolved);

    return Opacity(
      opacity: missing ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          // Selection is a fill *and* a border, so it reads on a busy
          // wallpaper where either alone could disappear.
          color: selected
              ? theme.surfacePressed.atMostAlpha(0.55)
              : hovered
                  ? theme.surfaceHover.atMostAlpha(0.28)
                  : null,
          border: Border.all(
            color: selected ? theme.accent : const Color(0x00000000),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: DesktopItemIcon(
                item: item,
                resolved: resolved,
                iconName: iconName,
                size: iconSize,
                foreground: theme.foreground,
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontFamily: theme.fontFamily,
                    color: theme.foreground,
                    // The wallpaper underneath is arbitrary, so the label needs
                    // its own contrast rather than relying on the theme's.
                    shadows: const [
                      Shadow(blurRadius: 3, color: Color(0xCC000000)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The in-place rename editor: the item's icon with its label replaced by a text
/// field.
///
/// Enter commits, Escape cancels, and so does losing focus — clicking away is the
/// third way out and must not leave a half-typed name on screen. The field only
/// receives keys because the host has flipped the background surface's keyboard
/// mode to `onDemand` for the duration.
class DesktopRenameField extends StatefulWidget {
  const DesktopRenameField({
    super.key,
    required this.item,
    required this.iconSize,
    required this.onCommit,
    required this.onCancel,
    this.resolved,
    this.iconName = '',
  });

  final DesktopItem item;
  final double iconSize;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final AppEntry? resolved;
  final String iconName;

  @override
  State<DesktopRenameField> createState() => _DesktopRenameFieldState();
}

class _DesktopRenameFieldState extends State<DesktopRenameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// Set once the rename is resolved, so the focus-loss handler that follows a
  /// commit does not fire a second, cancelling callback.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: labelForItem(widget.item, resolved: widget.resolved),
    );
    // Select the whole name: renaming usually means replacing, and the caret
    // sitting at the end would make the user clear it by hand first.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus || _resolved) return;
    _resolved = true;
    widget.onCancel();
  }

  void _commit() {
    if (_resolved) return;
    _resolved = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_resolved) return;
    _resolved = true;
    widget.onCancel();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.surfacePressed.atMostAlpha(0.55),
        border: Border.all(color: theme.accent, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.iconSize,
            height: widget.iconSize,
            child: DesktopItemIcon(
              item: widget.item,
              resolved: widget.resolved,
              iconName: widget.iconName,
              size: widget.iconSize,
              foreground: theme.foreground,
            ),
          ),
          const SizedBox(height: 4),
          // The shell has no WidgetsApp, so the default editing key bindings
          // (Backspace, arrows, Ctrl+A…) are absent unless supplied here — the
          // same trap `SettingsOverlay` documents.
          DefaultTextEditingShortcuts(
            child: Focus(
              onKeyEvent: _onKey,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.controlSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: EditableText(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _commit(),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                  cursorColor: theme.accentText,
                  backgroundCursorColor: theme.muted,
                  selectionColor: theme.accent.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The icon for one item, picking the renderer from its kind.
///
/// [iconName] is resolved by the grid, never here: `iconNameForItem` reaches
/// GIO, and doing that from `build` would guess the content type on every
/// frame. See `DesktopLayerState._syncResolved`.
class DesktopItemIcon extends StatelessWidget {
  const DesktopItemIcon({
    super.key,
    required this.item,
    required this.size,
    required this.foreground,
    this.resolved,
    this.iconName = '',
  });

  final DesktopItem item;
  final double size;
  final Color foreground;
  final AppEntry? resolved;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    // An application reuses the shared widget, so a pinned desktop icon and the
    // same app in the launcher look identical.
    if (item.kind == DesktopItemKind.app) {
      final entry = resolved;
      return AppIconImage(
        iconName: entry?.iconName ?? iconName,
        name: labelForItem(item, resolved: entry),
        size: size.round(),
        foreground: foreground,
      );
    }

    if (iconName.isEmpty) return _fallback();
    return XdgIcon(
      name: iconName,
      size: size.round(),
      iconNotFoundBuilder: _fallback,
    );
  }

  Widget _fallback() {
    // There are no bundled asset icons in this repo, so the last resort is a
    // font glyph rather than an image.
    return Center(
      child: FaIcon(
        item.kind == DesktopItemKind.folder
            ? FontAwesomeIcons.solidFolder
            : FontAwesomeIcons.file,
        size: size * 0.8,
        color: foreground,
      ),
    );
  }
}
