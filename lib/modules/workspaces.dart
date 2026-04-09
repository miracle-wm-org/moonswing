import 'package:flutter/widgets.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:miracle/miracle.dart';

class Workspaces extends StatefulWidget {
  const Workspaces({super.key});

  @override
  WorkspacesState createState() => WorkspacesState();
}

class WorkspacesState extends State<Workspaces> {
  List<WorkspaceResult> _workspaces = <WorkspaceResult>[];
  bool _initialized = false;
  late MiracleConnection _connection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _connection = MiracleScope.of(context);
      _connection.subscribe([SubscriptionType.workspace]);
      _connection.listen((Event event) {
        if (event is EventWorkspace) {
          _connection.getWorkspaces().then(_updateWorkspaces);
        }
      });
      _connection.getWorkspaces().then(_updateWorkspaces);
    }
  }

  void _updateWorkspaces(List<WorkspaceResult> workspaces) {
    setState(() {
      _workspaces = workspaces;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
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
                _connection.command(command);
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
