import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pulseaudio/pulseaudio.dart';

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

  @override
  void initState() {
    super.initState();
    _initPulseAudio();
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    _client?.dispose();
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

  IconData _volumeIcon() {
    if (_muted) return FontAwesomeIcons.volumeXmark;
    if (_volume <= 0.0) return FontAwesomeIcons.volumeOff;
    if (_volume <= 0.5) return FontAwesomeIcons.volumeLow;
    return FontAwesomeIcons.volumeHigh;
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();

    return Row(
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
    );
  }
}
