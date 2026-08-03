import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:miracle/miracle.dart';

class Workspaces extends StatefulWidget {
  const Workspaces({super.key});

  @override
  WorkspacesState createState() => WorkspacesState();
}

class WorkspacesState extends State<Workspaces> {
  List<WorkspaceResult> _workspaces = <WorkspaceResult>[];
  MiracleManager? _manager;
  MiracleConnection? _connection;
  StreamSubscription<Event>? _events;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = MiracleScope.of(context);
    if (manager != _manager) {
      _manager?.removeListener(_onManagerChanged);
      _manager = manager..addListener(_onManagerChanged);
    }
    _syncConnection();
  }

  @override
  void dispose() {
    _manager?.removeListener(_onManagerChanged);
    _events?.cancel();
    super.dispose();
  }

  void _onManagerChanged() {
    if (!mounted) return;
    // Rebuild even when the connection itself is unchanged — the connecting
    // flag drives the spinner.
    setState(_syncConnection);
  }

  /// Attaches to the manager's current connection, tearing down the listener on
  /// whichever connection it replaces. A [MiracleConnection] is single-use, so
  /// every reconnect hands us a different instance.
  void _syncConnection() {
    final connection = _manager?.connection;
    if (identical(connection, _connection)) return;

    _events?.cancel();
    _events = null;
    _connection = connection;
    _workspaces = <WorkspaceResult>[];

    if (connection == null) return;
    _events = connection.listen((Event event) {
      if (event is EventWorkspace) {
        connection.getWorkspaces().then(_updateWorkspaces);
      }
    });
    connection.getWorkspaces().then(_updateWorkspaces);
  }

  void _updateWorkspaces(List<WorkspaceResult> workspaces) {
    if (!mounted) return;
    setState(() {
      _workspaces = workspaces;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final connection = _connection;

    if (connection == null) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: (_manager?.connecting ?? false)
            ? SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: LoadingIndicator(
                    color: theme.foreground.withValues(alpha: 0.6),
                    size: 12,
                  ),
                ),
              )
            : const _MiracleRetryButton(),
      );
    }

    final outputName = DisplayScope.of(context).name;
    final visibleWorkspaces =
        _workspaces.where((ws) => ws.output == outputName).toList();
    return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          spacing: 4,
          children: visibleWorkspaces.map((workspace) {
            return _WorkspaceButton(
              key: ValueKey(workspace.num ?? workspace.name),
              backgroundColor:
                  workspace.focused ? theme.accent : theme.workspaceBackground,
              hoverColor: theme.surfaceHover,
              pressedColor: theme.surfacePressed,
              onPressed: () {
                final String command = workspace.num != null
                    ? 'workspace ${workspace.num}'
                    : 'workspace ${workspace.name}';
                connection.command(command);
              },
              child: Text(
                workspace.name ?? workspace.num?.toString() ?? '?',
                style: TextStyle(color: theme.foreground),
              ),
            );
          }).toList(),
        ));
  }
}

/// Stands in for the workspace row while the shell has no Miracle connection.
/// One click retries for every bar at once — the connection is shell-wide.
class _MiracleRetryButton extends StatefulWidget {
  const _MiracleRetryButton();

  @override
  State<_MiracleRetryButton> createState() => _MiracleRetryButtonState();
}

class _MiracleRetryButtonState extends State<_MiracleRetryButton>
    with PopupHost<_MiracleRetryButton> {
  bool _hovered = false;

  void _openTooltip(BuildContext context) {
    if (isPopupOpen) return;
    final error = MiracleScope.of(context).lastError;
    openBarPopup(
      context,
      child: ThemeProvider(
        child: TooltipLabel(
          text: error == null
              ? 'Not connected to Miracle — click to retry'
              : 'Not connected to Miracle — click to retry\n$error',
        ),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 64),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hovered) _openTooltip(context);
        });
      },
      onExit: (_) {
        setState(() => _hovered = false);
        closePopup();
      },
      child: _WorkspaceButton(
        backgroundColor: theme.workspaceBackground,
        hoverColor: theme.surfaceHover,
        pressedColor: theme.surfacePressed,
        onPressed: () {
          closePopup();
          MiracleScope.of(context).connect();
        },
        child: FaIcon(
          FontAwesomeIcons.arrowsRotate,
          size: 10,
          color: theme.foreground,
        ),
      ),
    );
  }
}

class _WorkspaceButton extends StatefulWidget {
  const _WorkspaceButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    this.backgroundColor = const Color(0xFF3A3A3A),
    this.hoverColor = const Color(0xFF4A4A4A),
    this.pressedColor = const Color(0xFF2A2A2A),
    this.borderRadius = 6,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color hoverColor;
  final Color pressedColor;
  final double borderRadius;

  @override
  State<_WorkspaceButton> createState() => _WorkspaceButtonState();
}

class WorkspacesModule extends Module {
  @override
  String get configKey => 'workspaces';

  @override
  void loadConfig(Map<String, dynamic>? map) {}

  @override
  WidgetBuilder get builder => (_) => const Workspaces();
}

class _WorkspaceButtonState extends State<_WorkspaceButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;

    Color color = widget.backgroundColor;
    if (!enabled) {
      color = color.withOpacity(0.5);
    } else if (_pressed) {
      color = widget.pressedColor;
    } else if (_hovered) {
      color = widget.hoverColor;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: SizedBox(
              width: 16, height: 16, child: Center(child: widget.child)),
        ),
      ),
    );
  }
}
