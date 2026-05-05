// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/pulse_client.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class SoundControl extends StatefulWidget {
  const SoundControl({super.key});

  @override
  SoundControlState createState() => SoundControlState();
}

class SoundControlState extends State<SoundControl>
    with PopupHost<SoundControl> {
  double _volume = 0.0;
  bool _muted = false;
  bool _available = false;
  String _defaultSinkName = '';
  PulseClient? _client;
  StreamSubscription<PaSink>? _sinkChangedSub;

  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _initPulseAudio();
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    closePopup();
    super.dispose();
  }

  Future<void> _initPulseAudio() async {
    try {
      final client = PulseClient();
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
    if (isPopupOpen) {
      closePopup();
      return;
    }

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
    final theme = ThemeScope.of(context);

    openPopup(
      context,
      anchorRect: anchorRect,
      parentAnchor: parentAnchor,
      childAnchor: childAnchor,
      preferredConstraints: isVertical
          ? const BoxConstraints.tightFor(width: 80, height: 200)
          : const BoxConstraints.tightFor(width: 240, height: 50),
      child: ThemeScope(
        theme: theme,
        child: _SoundPopupContent(
          volume: _volume,
          muted: _muted,
          vertical: isVertical,
          onVolumeChanged: (v) => client?.setSinkVolume(sinkName, v),
          onMuteToggled: () => client?.setSinkMute(sinkName, !_muted),
        ),
      ),
    );
  }

  FaIconData _volumeIcon() {
    if (_muted) return FontAwesomeIcons.volumeXmark;
    if (_volume <= 0.0) return FontAwesomeIcons.volumeOff;
    if (_volume <= 0.5) return FontAwesomeIcons.volumeLow;
    return FontAwesomeIcons.volumeHigh;
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();

    final theme = ThemeScope.of(context);
    final isActive = _hovered || isPopupOpen;
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
                color: theme.foreground,
              ),
              const SizedBox(width: 4),
              Text(
                '${(_volume * 100).round()}%',
                style: TextStyle(fontSize: 16, color: theme.foreground),
              ),
            ],
          ),
        ),
      ),
    );
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

  FaIconData _volumeIcon() {
    if (_muted) return FontAwesomeIcons.volumeXmark;
    if (_volume <= 0.0) return FontAwesomeIcons.volumeOff;
    if (_volume <= 0.5) return FontAwesomeIcons.volumeLow;
    return FontAwesomeIcons.volumeHigh;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final muteButton = GestureDetector(
      onTap: () {
        final newMuted = !_muted;
        setState(() => _muted = newMuted);
        widget.onMuteToggled();
      },
      child: FaIcon(
        _volumeIcon(),
        size: 14,
        color: _muted ? theme.muted : theme.popupForeground,
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
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupBounceIn(
          child: Container(
            color: theme.popupBackground,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: content,
          ),
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
    final theme = ThemeScope.of(context);
    final painter = _SliderPainter(
      value: value,
      enabled: enabled,
      axis: axis,
      trackColor: theme.sliderTrack,
      activeFillColor: theme.accent,
      inactiveFillColor: theme.sliderTrack,
      activeThumbColor: theme.popupForeground,
      inactiveThumbColor: theme.sliderTrack,
    );

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
          painter: painter,
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
        painter: painter,
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.value,
    required this.enabled,
    required this.trackColor,
    required this.activeFillColor,
    required this.inactiveFillColor,
    required this.activeThumbColor,
    required this.inactiveThumbColor,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final Axis axis;
  final Color trackColor;
  final Color activeFillColor;
  final Color inactiveFillColor;
  final Color activeThumbColor;
  final Color inactiveThumbColor;

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
          ..color = trackColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

      // Track fill (bottom up)
      if (thumbY < size.height) {
        canvas.drawLine(
          Offset(trackX, size.height),
          Offset(trackX, thumbY),
          Paint()
            ..color = enabled ? activeFillColor : inactiveFillColor
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }

      // Thumb
      canvas.drawCircle(
        Offset(trackX, thumbY),
        6,
        Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
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
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Track fill
    if (thumbX > 0) {
      canvas.drawLine(
        Offset(0, trackY),
        Offset(thumbX, trackY),
        Paint()
          ..color = enabled ? activeFillColor : inactiveFillColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Thumb
    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.value != value ||
      old.enabled != enabled ||
      old.axis != axis ||
      old.trackColor != trackColor ||
      old.activeFillColor != activeFillColor ||
      old.activeThumbColor != activeThumbColor;
}

class SoundControlModule extends Module {
  @override
  String get configKey => 'sound_control';

  @override
  void loadConfig(Map<String, dynamic>? map) {}

  @override
  WidgetBuilder get builder => (_) => const SoundControl();
}
