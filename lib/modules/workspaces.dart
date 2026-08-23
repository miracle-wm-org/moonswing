import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_services.dart';
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

  /// The [MiracleManager.outputsRevision] this row's list was fetched against.
  int _outputsRevision = 0;

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
    _refetchIfOutputsMoved();
  }

  /// Re-queries the workspace list when the shell's output set has changed
  /// since it was fetched.
  ///
  /// Miracle re-homes a removed output's workspaces onto another output without
  /// emitting a workspace event, so the cached `workspace -> output` mapping
  /// this row filters on can be stale with nothing on the event stream to say
  /// so. [MiracleManager.outputsRevision] is the shell's own `wl_output` view of
  /// the same reconfiguration.
  void _refetchIfOutputsMoved() {
    final revision = _manager?.outputsRevision ?? 0;
    if (revision == _outputsRevision) return;
    _outputsRevision = revision;
    _connection?.getWorkspaces().then(_updateWorkspaces);
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
    _outputsRevision = _manager?.outputsRevision ?? 0;

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

  /// The placeholder that stands in for the workspace row while something it
  /// needs is still on its way. One button's worth of space, so the modules
  /// beside it do not shuffle sideways when the row arrives.
  Widget _pending(ThemeConfig theme) => Padding(
        padding: const EdgeInsets.all(4.0),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: LoadingIndicator(
              color: theme.foreground.withValues(alpha: 0.6),
              size: 12,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final connection = _connection;

    if (connection == null) {
      // The IPC connect is started after the shell's first frame, so for the
      // first moments the manager is not yet even *connecting*. Asking the
      // service registry as well is what keeps the retry button — which means
      // "this failed" — from flashing up before anything has been tried.
      final pending = (_manager?.connecting ?? false) ||
          ShellServicesScope.isLoading(context, ShellService.miracle);
      return pending
          ? _pending(theme)
          : const Padding(
              padding: EdgeInsets.all(4.0),
              child: _MiracleRetryButton(),
            );
    }

    // Bars paint before Wayland output enumeration finishes, so which display
    // this one is on may not be known yet. Filtering on an unknown name would
    // render an empty row that then popped full.
    // `WaylandOutput.name` is non-nullable and starts empty, so an output that
    // is bound but has not delivered its `name` yet would otherwise pass this
    // guard and filter every workspace away — an empty row, not a loader.
    final outputName = DisplayScope.of(context)?.name;
    if (outputName == null || outputName.isEmpty) return _pending(theme);

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
      // A hover label displaces nothing — see the dock's tooltip.
      policy: TransientPolicy.tooltip,
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
    this.backgroundColor = const Color(0xFF3A3A3A),
    this.hoverColor = const Color(0xFF4A4A4A),
    this.pressedColor = const Color(0xFF2A2A2A),
  });

  /// Fixed, not parameters: every call site took the defaults.
  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 4, vertical: 4);
  static const double _borderRadius = 6;

  final VoidCallback? onPressed;
  final Widget child;
  final Color backgroundColor;
  final Color hoverColor;
  final Color pressedColor;

  @override
  State<_WorkspaceButton> createState() => _WorkspaceButtonState();
}

final Module workspacesModule = Module.plain(
  configKey: 'workspaces',
  builder: (_) => const Workspaces(),
);

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
          padding: _WorkspaceButton._padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius:
                BorderRadius.circular(_WorkspaceButton._borderRadius),
          ),
          child: SizedBox(
              width: 16, height: 16, child: Center(child: widget.child)),
        ),
      ),
    );
  }
}
