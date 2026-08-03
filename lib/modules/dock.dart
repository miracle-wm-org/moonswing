import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/modules/app_directory.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

class DockConfig {
  final List<String> apps;
  final int iconSize;

  /// Whether the app-directory button (and its divider) is shown at the end of
  /// the dock.
  final bool showAppDirectory;

  const DockConfig({
    this.apps = const [],
    this.iconSize = 24,
    this.showAppDirectory = true,
  });

  factory DockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DockConfig();
    return DockConfig(
      apps: (map['apps'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      iconSize: map['icon_size'] as int? ?? 24,
      showAppDirectory: map['show_app_directory'] as bool? ?? true,
    );
  }
}

// Data model

class _DockApp {
  /// The config id (as stored in `[modules.dock].apps`), used for unpinning.
  final String appId;
  final AppEntry entry;

  const _DockApp({required this.appId, required this.entry});
}

// Dock widget

class Dock extends StatefulWidget {
  const Dock({super.key, required this.config});

  final DockConfig config;

  @override
  DockState createState() => DockState();
}

class DockState extends State<Dock> {
  List<_DockApp> _apps = [];

  @override
  void initState() {
    super.initState();
    _loadApps(widget.config);
  }

  @override
  void didUpdateWidget(Dock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live config edit (e.g. pin/unpin writing to `[modules.dock].apps`)
    // rebuilds this widget with a fresh DockConfig. Reload only when the pinned
    // set actually changed so unrelated edits don't thrash the GIO lookups.
    if (!_sameList(oldWidget.config.apps, widget.config.apps)) {
      _loadApps(widget.config);
    }
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _loadApps(DockConfig config) {
    final apps = <_DockApp>[];
    for (final appId in config.apps) {
      final entry = loadAppById(appId);
      if (entry == null) continue;
      apps.add(_DockApp(appId: appId, entry: entry));
    }
    // Release the previously-resolved GAppInfo pointers before swapping.
    final previous = _apps;
    setState(() {
      _apps = apps;
    });
    disposeAppEntries(previous.map((a) => a.entry));
  }

  @override
  void dispose() {
    disposeAppEntries(_apps.map((a) => a.entry));
    super.dispose();
  }

  void _launch(_DockApp app) => launchApp(app.entry.appInfo);

  @override
  Widget build(BuildContext context) {
    final showDirectory = widget.config.showAppDirectory;
    if (_apps.isEmpty && !showDirectory) return const SizedBox.shrink();

    final size = widget.config.iconSize;
    final foreground = ThemeScope.of(context).foreground;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        for (final app in _apps)
          _DockButton(
            appId: app.appId,
            appName: app.entry.name,
            onPressed: () => _launch(app),
            child: AppIconImage(
              iconName: app.entry.iconName,
              name: app.entry.name,
              size: size,
              foreground: foreground,
            ),
          ),
        if (showDirectory) ...[
          _DockDivider(height: size.toDouble()),
          AppDirectoryButton(iconSize: size),
        ],
      ],
    );
  }
}

/// Thin vertical rule separating the pinned apps from the directory button.
class _DockDivider extends StatelessWidget {
  const _DockDivider({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: ThemeScope.of(context).divider,
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({
    required this.appId,
    required this.appName,
    required this.onPressed,
    required this.child,
  });

  final String appId;
  final String appName;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> with PopupHost<_DockButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _openTooltip(BuildContext context) {
    if (isPopupOpen) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    openBarPopup(
      context,
      child: ThemeProvider(child: TooltipLabel(text: widget.appName)),
      preferredConstraints: const BoxConstraints(maxWidth: 120, maxHeight: 32),
    );
  }

  void _openUnpinMenu(BuildContext context) {
    // Replace any open tooltip with the context menu.
    closePopup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openBarPopup(
        context,
        // Loose: the menu sizes to its content (see [ContextMenuCard]).
        preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
        child: ThemeProvider(
          child: PopupBounceIn(
            child: ContextMenuCard(
              items: [
                ContextMenuItem(
                  label: 'Unpin from dock',
                  onTap: () {
                    _unpin();
                    closePopup();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _unpin() {
    final store = ConfigStore.instance;
    final list = store.getList<String>(['modules', 'dock', 'apps']);
    if (!list.contains(widget.appId)) return;
    store.set(
      ['modules', 'dock', 'apps'],
      [...list]..remove(widget.appId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    Color color = const Color(0x00000000);
    if (_pressed) {
      color = theme.surfacePressed;
    } else if (_hovered) {
      color = theme.surfaceHover;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hovered) _openTooltip(context);
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
        closePopup();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapDown: (_) => _openUnpinMenu(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class DockModule extends Module {
  DockConfig _config = const DockConfig();

  @override
  String get configKey => 'dock';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = DockConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Dock(config: _config);
}
