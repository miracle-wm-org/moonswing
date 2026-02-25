// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pulseaudio/pulseaudio.dart';
import 'package:graceful_shell/layer_shell.dart';

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

    // Use WindowScope.of to get the LayershellWindowController for this view.
    final parentController = WindowScope.of(context);

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Use the full bar height so the popup is flush with the bar's bottom edge,
    // rather than the button widget's bottom (which would leave a gap).
    final flutterView = View.of(context);
    final barHeight =
        flutterView.physicalSize.height / flutterView.devicePixelRatio;

    // anchorRect is in screen coordinates (layer shell panel originates at 0,0).
    final anchorRect = Rect.fromLTWH(offset.dx, 0, size.width, 0);

    _popupController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: const WindowPositioner(
        parentAnchor: WindowPositionerAnchor.bottom,
        childAnchor: WindowPositionerAnchor.top,
      ),
      preferredConstraints:
          const BoxConstraints.tightFor(width: 200, height: 120),
      delegate: _SoundPopupDelegate(onDestroyed: _closePopup),
    );

    _popupView = PopupWindow(
      controller: _popupController!,
      child: _SoundPopupContent(
        volume: _volume,
        muted: _muted,
        onClose: _closePopup,
      ),
    );
    PopupManager.instance.add(_popupView!);
  }

  void _closePopup() {
    if (_popupView != null) {
      PopupManager.instance.remove(_popupView!);
      _popupView = null;
    }
    final ctrl = _popupController;
    _popupController = null;
    if (ctrl is PopupGtkWindowController && !ctrl.isDestroyed) {
      ctrl.destroy();
    }
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

    return GestureDetector(
      onTap: () => _togglePopup(context),
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

class _SoundPopupContent extends StatelessWidget {
  const _SoundPopupContent({
    required this.volume,
    required this.muted,
    required this.onClose,
  });

  final double volume;
  final bool muted;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
        child: Container(
          color: const Color(0xFF1E1E2E),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(muted ? 'Muted' : 'Volume: ${(volume * 100).round()}%'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onClose,
                child: const Text(
                  'Close',
                  style: TextStyle(color: Color(0xFF89DCEB)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
