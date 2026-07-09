// ignore_for_file: library_private_types_in_public_api

import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/settings/audio.dart';
import 'package:graceful_shell/settings/bluetooth.dart';
import 'package:graceful_shell/settings/display.dart';
import 'package:graceful_shell/settings/network.dart';
import 'package:graceful_shell/settings/shell.dart';
import 'package:graceful_shell/scopes.dart';

class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

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

  String _selectedCategory = 'network';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
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
    );
  }

  Widget _buildAnimated(ThemeConfig theme) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: const Color(0x882C2C2C),
              child: Center(
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: _buildPanel(theme),
    );
  }

  Widget _buildPanel(ThemeConfig theme) {
    return Container(
      width: 800,
      height: 560,
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.only(left: 24, right: 12, top: 12, bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.divider),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                MouseRegion(
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
                            color: theme.popupForeground.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body: sidebar + content
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
        return const ShellSettingsPage();
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
