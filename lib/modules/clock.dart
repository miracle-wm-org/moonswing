import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/overlay/overlay.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/timers/timer_store.dart';
import 'package:graceful_shell/timers/timer_widgets.dart';

class ClockConfig {
  final bool showDate;

  const ClockConfig({this.showDate = true});

  factory ClockConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClockConfig();
    return ClockConfig(
      showDate: map.boolOr('show_date', true),
    );
  }
}

class Clock extends StatefulWidget {
  const Clock({super.key, required this.config, this.timers});

  final ClockConfig config;

  /// Where the running timers and stopwatches come from, defaulting to the
  /// singleton. Injected by widget tests, which drive a store with no ticker
  /// behind it — a pending [Timer] fails the binding's end-of-test invariants.
  final TimersStore? timers;

  @override
  ClockState createState() => ClockState();
}

// ignore: library_private_types_in_public_api
class ClockState extends State<Clock>
    with LayerShellHost<Clock>, PopupHost<Clock> {
  late String _timeString;
  late String _dateString;
  Timer? _timer;
  bool _hovered = false;

  final ValueNotifier<bool> _closingNotifier = ValueNotifier(false);

  TimersStore get _timers => widget.timers ?? TimersStore.instance;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timeString = _formatTime(now);
    _dateString = _formatDate(now);
    _scheduleNextTick();
    _timers.addListener(_onTimersChanged);
  }

  /// The last timer being stopped takes the readout out of the bar, so the
  /// popup hanging off it has to go too — otherwise it sits there anchored to
  /// a button that no longer exists, with nothing in it.
  void _onTimersChanged() {
    if (isPopupOpen && _timers.isEmpty) closePopup();
  }

  void _toggleTimersPopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      // Width pinned, height hugging its rows: this card rebuilds while it is
      // open, so a content-*width* one would walk away from its button as the
      // digits changed. Starting a timer is only possible from the calendar
      // overlay, which dismisses this popup on its way up, so rows can leave the
      // card while it is open but never arrive.
      preferredConstraints: const BoxConstraints(
        minWidth: kTimersPopupWidth,
        maxWidth: kTimersPopupWidth,
        maxHeight: 320,
      ),
      child: ThemeProvider(
        child: TimersPopupContent(store: widget.timers),
      ),
    );
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
    _timers.removeListener(_onTimersChanged);
    closePopup();
    closeLayerWindow();
    _closingNotifier.dispose();
    super.dispose();
  }

  void _toggleOverlay(BuildContext context) {
    if (isLayerWindowOpen) {
      _beginCloseOverlay();
    } else {
      _openOverlay(context);
    }
  }

  void _openOverlay(BuildContext context) {
    _closingNotifier.value = false;

    final controller = LayershellWindowController(
      layer: LayerShellLayer.overlay,
      anchorEdges: [
        LayerShellEdge.top,
        LayerShellEdge.bottom,
        LayerShellEdge.left,
        LayerShellEdge.right,
      ],
      keyboardMode: LayerShellKeyboardMode.onDemand,
    );
    // Full-screen means the whole output, panels included.
    spanFullOutput(controller);

    openLayerWindow(
      context,
      controller: controller,
      // The coordinator gets the fade-out, not the teardown: dismissing this
      // straight to closeLayerWindow would make the overlay vanish instead of
      // playing the exit SettingsOverlay owns.
      onDismissRequested: _beginCloseOverlay,
      child: ThemeProvider(
        child: SettingsOverlay(
          closingNotifier: _closingNotifier,
          onClosed: _onOverlayClosed,
        ),
      ),
    );
  }

  void _beginCloseOverlay() {
    _closingNotifier.value = true;
    // SettingsOverlay plays its fade-out then calls _onOverlayClosed.
  }

  void _onOverlayClosed() {
    closeLayerWindow();
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only the date and time open the overlay. The timers readout beside
        // them is its own gesture region, or stopping a timer from the bar
        // would mean opening the calendar first.
        MouseRegion(
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
        ),
        // Renders itself away when nothing is running, separator included.
        TimerBarIndicator(
          store: widget.timers,
          active: isPopupOpen,
          onTap: _toggleTimersPopup,
        ),
      ],
    );
  }
}

final Module clockModule = Module.simple(
  configKey: 'clock',
  fromMap: ClockConfig.fromMap,
  builder: (context, config) => Clock(config: config),
);
