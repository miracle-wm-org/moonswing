import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:miracle/miracle.dart';

final Color _focusedColor = const Color(0xFF4A90E2);

class Workspaces extends StatefulWidget {
  const Workspaces({super.key, required this.connection});

  final MiracleConnection connection;

  @override
  WorkspacesState createState() => WorkspacesState();
}

class WorkspacesState extends State<Workspaces> {
  List<WorkspaceResult> _workspaces = <WorkspaceResult>[];

  @override
  void initState() {
    super.initState();
    widget.connection.subscribe([SubscriptionType.workspace]);
    widget.connection.listen((Event event) {
      if (event is EventWorkspace) {
        widget.connection.getWorkspaces().then((workspaces) {
          _updateWorkspaces(workspaces);
        });
      }
    });

    widget.connection.getWorkspaces().then((workspaces) {
      _updateWorkspaces(workspaces);
    });
  }

  void _updateWorkspaces(List<WorkspaceResult> workspaces) {
    setState(() {
      _workspaces = workspaces;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          spacing: 4,
          children: _workspaces.map((workspace) {
            return _WorkspaceButton(
              key: ValueKey(workspace.num ?? workspace.name),
              backgroundColor:
                  workspace.focused ? _focusedColor : const Color(0xFF3A3A3A),
              onPressed: () {
                final String command = workspace.num != null
                    ? 'workspace ${workspace.num}'
                    : 'workspace ${workspace.name}';
                widget.connection.command(command);
              },
              child: Text(
                workspace.name ?? workspace.num?.toString() ?? '?',
                style: const TextStyle(color: Color(0xFFFFFFFF)),
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
