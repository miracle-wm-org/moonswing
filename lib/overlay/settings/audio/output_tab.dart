// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/host_process.dart';
import 'package:moonswing/pulse_client.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/audio/audio_slider.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// Tab 1 — Output Device
// ---------------------------------------------------------------------------

class OutputTab extends StatefulWidget {
  const OutputTab({super.key, required this.client});

  final PulseClient client;

  @override
  _OutputTabState createState() => _OutputTabState();
}

class _OutputTabState extends State<OutputTab> {
  List<PaSink>? _sinks;
  String _defaultSinkName = '';
  double _volume = 0.0;
  bool _muted = false;
  double _balance = 0.0;
  int _channelCount = 0;
  bool _loading = true;
  String? _error;
  bool _testingAudio = false;
  StreamSubscription<PaSink>? _sinkChangedSub;
  StreamSubscription<int>? _sinkRemovedSub;

  @override
  void initState() {
    super.initState();
    _load();
    _sinkChangedSub = widget.client.onSinkChanged.listen((sink) {
      if (sink.name == _defaultSinkName && mounted) {
        setState(() {
          _volume = sink.volume;
          _muted = sink.mute;
          _balance = sink.balance;
          _channelCount = sink.channelCount;
        });
      }
    });
    _sinkRemovedSub = widget.client.onSinkRemoved.listen((_) => _load());
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    _sinkRemovedSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final serverInfo = await widget.client.getServerInfo();
      final sinks = await widget.client.getSinkList();
      if (!mounted) return;
      final defaultName = serverInfo.defaultSinkName;
      PaSink? current;
      for (final s in sinks) {
        if (s.name == defaultName) {
          current = s;
          break;
        }
      }
      setState(() {
        _sinks = sinks;
        _defaultSinkName = defaultName;
        _volume = current?.volume ?? 0.0;
        _muted = current?.mute ?? false;
        _channelCount = current?.channelCount ?? 0;
        _balance = current?.balance ?? 0.0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectSink(String name) async {
    try {
      await widget.client.setDefaultSink(name);
      await _load();
    } catch (_) {}
  }

  Future<void> _applyVolume(double v) async {
    setState(() => _volume = v);
    await _applyVolumeBalance(v, _balance);
  }

  Future<void> _applyBalanceChange(double b) async {
    setState(() => _balance = b);
    await _applyVolumeBalance(_volume, b);
  }

  Future<void> _applyVolumeBalance(double vol, double balance) async {
    if (_defaultSinkName.isEmpty) return;
    try {
      if (_channelCount >= 2) {
        await widget.client.setSinkVolumeBalance(
            _defaultSinkName, vol, balance, _channelCount);
      } else {
        await widget.client.setSinkVolume(_defaultSinkName, vol);
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final newMuted = !_muted;
    setState(() => _muted = newMuted);
    try {
      await widget.client.setSinkMute(_defaultSinkName, newMuted);
    } catch (_) {}
  }

  Future<void> _testSpeakers() async {
    if (_testingAudio) return;
    setState(() => _testingAudio = true);
    try {
      await runHostProcess(
          'speaker-test', ['-t', 'sine', '-f', '440', '-l', '1', '-c', '2']);
    } catch (_) {}
    if (mounted) setState(() => _testingAudio = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_error != null) return _buildRetry(theme, _error!);
    if (_loading) return const Center(child: LoadingIndicator(size: 22));
    return _buildContent(theme);
  }

  Widget _buildRetry(ThemeConfig theme, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error,
              style: TextStyle(fontSize: 13, color: theme.accentText),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: SettingsActionButton(
              label: 'Retry',
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeConfig theme) {
    final sinks = _sinks!;
    final items = sinks
        .map((s) => SettingsDropdownItem<String>(value: s.name, label: s.description))
        .toList();
    final volPct = (_volume * 100).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsSectionLabel('Output Device'),
        const SizedBox(height: 8),
        SettingsDropdown<String>(
          items: items,
          selected: _defaultSinkName,
          onSelected: _selectSink,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const SettingsSectionLabel('Volume'),
            const Spacer(),
            SettingsIconButton(
              icon: _muted
                  ? FontAwesomeIcons.volumeXmark
                  : volPct == 0
                      ? FontAwesomeIcons.volumeOff
                      : volPct < 50
                          ? FontAwesomeIcons.volumeLow
                          : FontAwesomeIcons.volumeHigh,
              size: ShellFontSizes.label,
              color: _muted ? theme.muted : theme.popupForeground,
              onTap: _toggleMute,
            ),
            const SizedBox(width: 2),
            Text(
              '$volPct%',
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AudioSlider(
          value: _volume,
          min: 0.0,
          max: 1.5,
          warningThreshold: 1.0,
          enabled: !_muted,
          onChanged: (v) => setState(() => _volume = v),
          onChangeEnd: _applyVolume,
        ),
        if (_volume > 1.0) ...[
          const SizedBox(height: 4),
          Text(
            'Volume above 100% may distort audio',
            style: TextStyle(
                fontSize: 11, fontFamily: theme.fontFamily, color: theme.muted),
          ),
        ],
        if (_channelCount >= 2) ...[
          const SizedBox(height: 20),
          const SettingsSectionLabel('Balance'),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('L',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.6))),
              const SizedBox(width: 8),
              Expanded(
                child: AudioSlider(
                  value: _balance,
                  min: -1.0,
                  max: 1.0,
                  onChanged: (v) => setState(() => _balance = v),
                  onChangeEnd: _applyBalanceChange,
                ),
              ),
              const SizedBox(width: 8),
              Text('R',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.6))),
            ],
          ),
        ],
        const SizedBox(height: 20),
        SettingsActionButton(
          label: 'Test Speakers',
          loading: _testingAudio,
          onTap: _testSpeakers,
        ),
      ],
    );
  }
}
