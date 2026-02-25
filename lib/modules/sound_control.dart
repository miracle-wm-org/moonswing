// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pulseaudio/pulseaudio.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class SoundControl extends StatefulWidget {
  const SoundControl({super.key});

  @override
  SoundControlState createState() => SoundControlState();
}

class SoundControlState extends State<SoundControl> {
  double _volume = 0.0;
  bool _muted = false;
  bool _available = false;
  String _defaultSinkName = '';
  PulseAudioClient? _client;
  StreamSubscription<PulseAudioSink>? _sinkChangedSub;

  PopupWindowController? _popupController;
  PopupWindow? _popupView;
  bool _hovered = false;
  bool _popupHasBeenActive = false;

  @override
  void initState() {
    super.initState();
    _initPulseAudio();
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    _client?.dispose();
    _closePopup();
    super.dispose();
  }

  Future<void> _initPulseAudio() async {
    try {
      final client = PulseAudioClient();
      await client.initialize();
      _client = client;

      final serverInfo = await client.getServerInfo();
      _defaultSinkName = serverInfo.defaultSinkName;

      final sinks = await client.getSinkList();
      for (final sink in sinks) {
        if (sink.name == _defaultSinkName) {
          if (!mounted) return;
          setState(() {
            _volume = sink.volume;
            _muted = sink.mute;
            _available = true;
          });
          break;
        }
      }

      _sinkChangedSub = client.onSinkChanged.listen((sink) {
        if (sink.name == _defaultSinkName && mounted) {
          setState(() {
            _volume = sink.volume;
            _muted = sink.mute;
          });
        }
      });
    } catch (_) {
      // PulseAudio unavailable
    }
  }

  void _togglePopup(BuildContext context) {
    if (_popupController != null) {
      _closePopup();
      return;
    }

    final parentController = WindowScope.of(context);

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final flutterView = View.of(context);
    final dpr = flutterView.devicePixelRatio;
    final barLogicalWidth = flutterView.physicalSize.width / dpr;
    final barLogicalHeight = flutterView.physicalSize.height / dpr;

    final anchor = BarScope.of(context).anchor;

    // Compute anchor-aware popup position so the popup appears flush
    // against the correct edge of the bar for all four anchor sides.
    final Rect anchorRect;
    final WindowPositionerAnchor parentAnchor;
    final WindowPositionerAnchor childAnchor;

    switch (anchor) {
      case 'bottom':
        final screenH = getScreenSize().height;
        anchorRect =
            Rect.fromLTWH(offset.dx, screenH - barLogicalHeight, size.width, 0);
        parentAnchor = WindowPositionerAnchor.top;
        childAnchor = WindowPositionerAnchor.bottom;
      case 'left':
        anchorRect = Rect.fromLTWH(0, offset.dy, barLogicalWidth, size.height);
        parentAnchor = WindowPositionerAnchor.right;
        childAnchor = WindowPositionerAnchor.left;
      case 'right':
        final screenW = getScreenSize().width;
        anchorRect = Rect.fromLTWH(
            screenW - barLogicalWidth, offset.dy, barLogicalWidth, 0);
        parentAnchor = WindowPositionerAnchor.left;
        childAnchor = WindowPositionerAnchor.right;
      default: // 'top'
        anchorRect = Rect.fromLTWH(offset.dx, 0, size.width, 0);
        parentAnchor = WindowPositionerAnchor.bottom;
        childAnchor = WindowPositionerAnchor.top;
    }

    final client = _client;
    final sinkName = _defaultSinkName;
    final isVertical = anchor == 'top' || anchor == 'bottom';

    _popupController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints: isVertical
          ? const BoxConstraints.tightFor(width: 80, height: 200)
          : const BoxConstraints.tightFor(width: 240, height: 50),
      delegate: _SoundPopupDelegate(onDestroyed: _closePopup),
    );

    _popupView = PopupWindow(
      controller: _popupController!,
      child: _SoundPopupContent(
        volume: _volume,
        muted: _muted,
        vertical: isVertical,
        onVolumeChanged: (v) => client?.setSinkVolume(sinkName, v),
        onMuteToggled: () => client?.setSinkMute(sinkName, !_muted),
      ),
    );
    _popupHasBeenActive = false;
    _popupController!.addListener(_onPopupStateChanged);
    PopupManager.instance.add(_popupView!);
    setState(() {});
  }

  void _onPopupStateChanged() {
    final ctrl = _popupController;
    if (ctrl == null) return;
    if (ctrl.isActivated) {
      _popupHasBeenActive = true;
    } else if (_popupHasBeenActive) {
      _popupHasBeenActive = false;
      _closePopup();
    }
  }

  void _closePopup() {
    _popupController?.removeListener(_onPopupStateChanged);
    if (_popupView != null) {
      PopupManager.instance.remove(_popupView!);
      _popupView = null;
    }
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl is PopupGtkWindowController && !ctrl.isDestroyed) {
      ctrl.destroy();
    }
    if (mounted) setState(() {});
  }

  IconData _volumeIcon() {
    if (_muted) return FontAwesomeIcons.volumeXmark;
    if (_volume <= 0.0) return FontAwesomeIcons.volumeOff;
    if (_volume <= 0.5) return FontAwesomeIcons.volumeLow;
    return FontAwesomeIcons.volumeHigh;
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();

    final isActive = _hovered || _popupController != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _togglePopup(context),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0x28FFFFFF) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                _volumeIcon(),
                size: 12,
                color: const Color(0xFFE0E0E0),
              ),
              const SizedBox(width: 4),
              Text(
                '${(_volume * 100).round()}%',
                style: const TextStyle(fontSize: 16, color: Color(0xFFFFFFFF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundPopupDelegate extends PopupWindowControllerDelegate {
  _SoundPopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

class _SoundPopupContent extends StatefulWidget {
  const _SoundPopupContent({
    required this.volume,
    required this.muted,
    required this.vertical,
    required this.onVolumeChanged,
    required this.onMuteToggled,
  });

  final double volume;
  final bool muted;
  final bool vertical;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMuteToggled;

  @override
  _SoundPopupContentState createState() => _SoundPopupContentState();
}

class _SoundPopupContentState extends State<_SoundPopupContent> {
  late double _volume;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _volume = widget.volume;
    _muted = widget.muted;
  }

  IconData _volumeIcon() {
    if (_muted) return FontAwesomeIcons.volumeXmark;
    if (_volume <= 0.0) return FontAwesomeIcons.volumeOff;
    if (_volume <= 0.5) return FontAwesomeIcons.volumeLow;
    return FontAwesomeIcons.volumeHigh;
  }

  @override
  Widget build(BuildContext context) {
    final muteButton = GestureDetector(
      onTap: () {
        final newMuted = !_muted;
        setState(() => _muted = newMuted);
        widget.onMuteToggled();
      },
      child: FaIcon(
        _volumeIcon(),
        size: 14,
        color: _muted ? const Color(0xFFE06C75) : const Color(0xFFCDD6F4),
      ),
    );

    final volumeLabel = Text(_muted ? 'Muted' : '${(_volume * 100).round()}%');

    final content = widget.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              volumeLabel,
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: _VolumeSlider(
                  value: _muted ? 0.0 : _volume,
                  enabled: !_muted,
                  axis: Axis.vertical,
                  onChanged: (v) => setState(() => _volume = v),
                  onChangeEnd: (v) => widget.onVolumeChanged(v),
                ),
              ),
              const SizedBox(height: 10),
              muteButton,
            ],
          )
        : Row(
            children: [
              muteButton,
              const SizedBox(width: 8),
              Expanded(
                child: _VolumeSlider(
                  value: _muted ? 0.0 : _volume,
                  enabled: !_muted,
                  onChanged: (v) => setState(() => _volume = v),
                  onChangeEnd: (v) => widget.onVolumeChanged(v),
                ),
              ),
              const SizedBox(width: 8),
              volumeLabel,
            ],
          );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFCDD6F4), fontSize: 13),
        child: Container(
          color: const Color(0xFF1E1E2E),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: content,
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Axis axis;

  double _valueFromPosition(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    if (axis == Axis.vertical) {
      return (1.0 - local.dy / box.size.height).clamp(0.0, 1.0);
    }
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.vertical) {
      return GestureDetector(
        onVerticalDragUpdate: !enabled
            ? null
            : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
        onVerticalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
        onTapDown: !enabled
            ? null
            : (d) {
                final v = _valueFromPosition(context, d.globalPosition);
                onChanged(v);
                onChangeEnd(v);
              },
        child: CustomPaint(
          size: const Size(20, double.infinity),
          painter: _SliderPainter(value: value, enabled: enabled, axis: axis),
        ),
      );
    }
    return GestureDetector(
      onHorizontalDragUpdate: !enabled
          ? null
          : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
      onHorizontalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
      onTapDown: !enabled
          ? null
          : (d) {
              final v = _valueFromPosition(context, d.globalPosition);
              onChanged(v);
              onChangeEnd(v);
            },
      child: CustomPaint(
        size: const Size(double.infinity, 20),
        painter: _SliderPainter(value: value, enabled: enabled, axis: axis),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.value,
    required this.enabled,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    if (axis == Axis.vertical) {
      final trackX = size.width / 2;
      final thumbY = (1.0 - value) * size.height;

      // Track background
      canvas.drawLine(
        Offset(trackX, 0),
        Offset(trackX, size.height),
        Paint()
          ..color = const Color(0xFF45475A)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

      // Track fill (bottom up)
      if (thumbY < size.height) {
        canvas.drawLine(
          Offset(trackX, size.height),
          Offset(trackX, thumbY),
          Paint()
            ..color =
                enabled ? const Color(0xFF89B4FA) : const Color(0xFF585B70)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }

      // Thumb
      canvas.drawCircle(
        Offset(trackX, thumbY),
        6,
        Paint()
          ..color = enabled ? const Color(0xFFCDD6F4) : const Color(0xFF6C7086),
      );
      return;
    }

    final trackY = size.height / 2;
    final thumbX = value * size.width;

    // Track background
    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      Paint()
        ..color = const Color(0xFF45475A)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Track fill
    if (thumbX > 0) {
      canvas.drawLine(
        Offset(0, trackY),
        Offset(thumbX, trackY),
        Paint()
          ..color = enabled ? const Color(0xFF89B4FA) : const Color(0xFF585B70)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Thumb
    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()
        ..color = enabled ? const Color(0xFFCDD6F4) : const Color(0xFF6C7086),
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.value != value || old.enabled != enabled || old.axis != axis;
}

class SoundControlModule extends Module {
  @override
  String get configKey => 'sound_control';

  @override
  void loadConfig(Map<String, dynamic>? map) {}

  @override
  WidgetBuilder get builder => (_) => const SoundControl();
}
