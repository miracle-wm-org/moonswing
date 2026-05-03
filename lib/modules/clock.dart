// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:graceful_shell/gtk.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/settings/overlay.dart';
import 'package:graceful_shell/scopes.dart';

class ClockConfig {
  final bool showDate;

  const ClockConfig({this.showDate = true});

  factory ClockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClockConfig();
    return ClockConfig(
      showDate: map['show_date'] as bool? ?? true,
    );
  }
}

class Clock extends StatefulWidget {
  const Clock({super.key, required this.config});

  final ClockConfig config;

  @override
  ClockState createState() => ClockState();
}

// ignore: library_private_types_in_public_api
class ClockState extends State<Clock> {
  late String _timeString;
  late String _dateString;
  Timer? _timer;
  bool _hovered = false;

  LayershellWindowController? _overlayController;
  LayerShellWindow? _overlayView;
  final ValueNotifier<bool> _closingNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timeString = _formatTime(now);
    _dateString = _formatDate(now);
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final msUntilNextSecond = 1000 - now.millisecond;
    _timer = Timer(Duration(milliseconds: msUntilNextSecond), () {
      _updateTime();
      _scheduleNextTick();
    });
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _timeString = _formatTime(now);
      _dateString = _formatDate(now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _closeOverlay();
    _closingNotifier.dispose();
    super.dispose();
  }

  void _toggleOverlay(BuildContext context) {
    if (_overlayController != null) {
      _beginCloseOverlay();
    } else {
      _openOverlay(context);
    }
  }

  void _openOverlay(BuildContext context) {
    final owner =
        WidgetsBinding.instance.windowingOwner as ExtendedWindowingOwnerLinux;

    _closingNotifier.value = false;

    _overlayController = LayershellWindowController(
      owner: owner,
      delegate: RegularWindowControllerDelegate(),
      layer: GtkLayerShellLayer.overlay,
      anchorEdges: [
        GtkLayerShellEdge.top,
        GtkLayerShellEdge.bottom,
        GtkLayerShellEdge.left,
        GtkLayerShellEdge.right,
      ],
      keyboardMode: GtkLayerShellKeyboardMode.onDemand,
    );

    final theme = ThemeScope.of(context);

    _overlayView = LayerShellWindow(
      controller: _overlayController!,
      child: ThemeScope(
        theme: theme,
        child: SettingsOverlay(
          closingNotifier: _closingNotifier,
          onClosed: _onOverlayClosed,
        ),
      ),
    );

    DynamicLayerShellViews.instance.add(_overlayView!);
    setState(() {});
  }

  void _beginCloseOverlay() {
    _closingNotifier.value = true;
    // SettingsOverlay plays its fade-out then calls _onOverlayClosed.
  }

  void _onOverlayClosed() {
    _closeOverlay();
  }

  void _closeOverlay() {
    if (_overlayView != null) {
      DynamicLayerShellViews.instance.remove(_overlayView!);
      _overlayView = null;
    }
    final ctrl = _overlayController;
    _overlayController = null;
    ctrl?.destroy();
    if (mounted) setState(() {});
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${_months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final style = TextStyle(fontSize: 16, color: theme.foreground);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _toggleOverlay(context),
        child: Container(
          decoration: BoxDecoration(
            color: _hovered ? theme.surfaceHover : null,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.config.showDate) ...[
                Text(_dateString, style: style),
                const SizedBox(width: 8),
              ],
              Text(_timeString, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

class ClockModule extends Module {
  ClockConfig _config = const ClockConfig();

  @override
  String get configKey => 'clock';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = ClockConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => Clock(config: _config);
}
