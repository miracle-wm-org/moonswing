// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/pulse_client.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/audio/audio_slider.dart';
import 'package:moonswing/overlay/settings/audio/level_meter.dart';
import 'package:moonswing/overlay/settings/audio/pulse_helpers.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// Tab 2 — Input Device
// ---------------------------------------------------------------------------

class InputTab extends StatefulWidget {
  const InputTab({super.key, required this.client});

  final PulseClient client;

  @override
  _InputTabState createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  List<PaSource>? _sources;
  String _defaultSourceName = '';
  double _volume = 0.0;
  bool _muted = false;
  // A notifier, not state: it moves thirty times a second, and only the meter
  // listens — a `setState` per reading rebuilt the whole page.
  final ValueNotifier<double> _level = ValueNotifier(0.0);
  bool _noiseSuppAvailable = false;
  bool _noiseSuppEnabled = false;
  bool _togglingNoiseSupp = false;
  bool _loading = true;

  /// The loopback behind "Hear microphone", or null while it is off. The page
  /// owns it: leaving the page turns it off.
  int? _monitorIndex;
  bool _togglingMonitor = false;
  bool _monitorFailed = false;
  String? _error;
  StreamSubscription<PaSource>? _sourceChangedSub;
  StreamSubscription<int>? _sourceRemovedSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<void>? _reconnectedSub;

  @override
  void initState() {
    super.initState();
    _load();
    _sourceChangedSub = widget.client.onSourceChanged.listen((source) {
      if (source.name == _defaultSourceName && mounted) {
        setState(() {
          _volume = source.volume;
          _muted = source.mute;
        });
      }
    });
    _sourceRemovedSub = widget.client.onSourceRemoved.listen((_) => _load());

    // The server went away and came back. The meter's `pa_stream` belonged to the
    // context that died, so a page left open across a `pipewire-pulse` restart
    // would sit on a meter that has stopped reporting — which reads as a dead
    // microphone. `_load` re-reads the list and ends in `_startMeter`.
    _reconnectedSub = widget.client.onReconnected.listen((_) {
      _levelSub?.cancel();
      _levelSub = null;
      // The loopback was a module of the server that died, so it is gone too;
      // the switch must not claim otherwise.
      if (mounted) setState(() => _monitorIndex = null);
      _load();
    });
  }

  @override
  void dispose() {
    _sourceChangedSub?.cancel();
    _sourceRemovedSub?.cancel();
    _reconnectedSub?.cancel();
    // Not `_stopMeter`, whose reset would repaint a meter being torn down.
    _levelSub?.cancel();
    widget.client.stopLevelMeter();
    _level.dispose();
    // Nobody is left on the page to switch it off, and a module outlives the
    // client that loaded it.
    final monitor = _monitorIndex;
    if (monitor != null) {
      widget.client.unloadModule(monitor).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final serverInfo = await widget.client.getServerInfo();
      final sources = await widget.client.getSourceList();
      final noiseSuppEnabled =
          await isModuleLoaded(widget.client, 'module-ladspa-source');
      // A monitor left behind by a shell that died with it on. Skipped while a
      // toggle is in flight, whose index is not yet known and would be swept.
      if (!_togglingMonitor) {
        await unloadMicMonitors(widget.client, keep: _monitorIndex);
      }
      if (!mounted) return;
      final filtered =
          sources.where((s) => !s.name.endsWith('.monitor')).toList();
      final defaultName = serverInfo.defaultSourceName;
      PaSource? current;
      for (final s in filtered) {
        if (s.name == defaultName) {
          current = s;
          break;
        }
      }
      // Check for the LADSPA plugin on disk instead of spawning `which`
      final noiseSuppAvail =
          File('/usr/lib/ladspa/librnnoise_ladspa.so').existsSync() ||
              File('/usr/local/lib/ladspa/librnnoise_ladspa.so').existsSync();
      setState(() {
        _sources = filtered;
        _defaultSourceName = defaultName;
        _volume = current?.volume ?? 0.0;
        _muted = current?.mute ?? false;
        _noiseSuppAvailable = noiseSuppAvail;
        _noiseSuppEnabled = noiseSuppEnabled;
        _loading = false;
        _error = null;
      });
      _startMeter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectSource(String name) async {
    _stopMeter();
    try {
      await widget.client.setDefaultSource(name);
      if (mounted) setState(() => _defaultSourceName = name);
      _startMeter();
      await _restartMonitor();
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final newMuted = !_muted;
    setState(() => _muted = newMuted);
    try {
      await widget.client.setSourceMute(_defaultSourceName, newMuted);
    } catch (_) {}
  }

  void _startMeter() {
    _stopMeter();
    if (_defaultSourceName.isEmpty) return;
    final levelStream = widget.client.startLevelMeter(_defaultSourceName);
    _levelSub = levelStream.listen((level) {
      if (mounted) _level.value = level;
    });
  }

  void _stopMeter() {
    _levelSub?.cancel();
    _levelSub = null;
    widget.client.stopLevelMeter();
    if (mounted) _level.value = 0.0;
  }

  Future<void> _toggleMonitor() async {
    if (_togglingMonitor) return;
    setState(() => _togglingMonitor = true);
    try {
      if (_monitorIndex != null) {
        await _stopMonitor();
      } else {
        await _startMonitor();
      }
    } catch (_) {
      if (mounted) setState(() => _monitorFailed = true);
    }
    if (mounted) setState(() => _togglingMonitor = false);
  }

  Future<void> _startMonitor() async {
    if (_defaultSourceName.isEmpty) return;
    final idx = await loadMicMonitor(widget.client, _defaultSourceName);
    if (!mounted) {
      // The page closed while the server was answering; dispose saw no index.
      if (idx != null) widget.client.unloadModule(idx).catchError((_) {});
      return;
    }
    setState(() {
      _monitorIndex = idx;
      _monitorFailed = idx == null;
    });
  }

  Future<void> _stopMonitor() async {
    final idx = _monitorIndex;
    if (idx == null) return;
    setState(() => _monitorIndex = null);
    await widget.client.unloadModule(idx);
  }

  /// Moves a running monitor onto the current source. A loopback cannot be
  /// retargeted, so it is replaced.
  Future<void> _restartMonitor() async {
    if (_monitorIndex == null || _togglingMonitor) return;
    _togglingMonitor = true;
    try {
      await _stopMonitor();
      await _startMonitor();
    } catch (_) {
      if (mounted) setState(() => _monitorFailed = true);
    }
    _togglingMonitor = false;
    if (mounted) setState(() {});
  }

  Future<void> _toggleNoiseSupp() async {
    if (_togglingNoiseSupp) return;
    setState(() => _togglingNoiseSupp = true);
    try {
      if (_noiseSuppEnabled) {
        final idx =
            await findModuleIndex(widget.client, 'module-ladspa-source');
        if (idx != null) await widget.client.unloadModule(idx);
        final first = _sources?.firstOrNull?.name;
        if (first != null) await widget.client.setDefaultSource(first);
      } else {
        await widget.client.loadModule(
          'module-ladspa-source',
          'source_name=denoised'
              ' master=$_defaultSourceName'
              ' plugin=librnnoise_ladspa'
              ' label=noise_suppressor_stereo',
        );
        await widget.client.setDefaultSource('denoised');
      }
      final enabled =
          await isModuleLoaded(widget.client, 'module-ladspa-source');
      if (mounted) setState(() => _noiseSuppEnabled = enabled);
      // The default source just changed under the page. Re-reading it points
      // the meter at it, and the monitor follows, so hearing yourself with
      // suppression on is hearing what the call hears.
      await _load();
      await _restartMonitor();
    } catch (_) {}
    if (mounted) setState(() => _togglingNoiseSupp = false);
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
    final sources = _sources!;
    final items = sources
        .map((s) => SettingsDropdownItem<String>(value: s.name, label: s.description))
        .toList();
    final volPct = (_volume * 100).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsSectionLabel('Input Device'),
        const SizedBox(height: 8),
        SettingsDropdown<String>(
          items: items,
          selected: _defaultSourceName,
          onSelected: _selectSource,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const SettingsSectionLabel('Gain'),
            const Spacer(),
            SettingsIconButton(
              icon: _muted
                  ? FontAwesomeIcons.microphoneSlash
                  : FontAwesomeIcons.microphone,
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
          onChangeEnd: (v) {
            try {
              widget.client.setSourceVolume(_defaultSourceName, v);
            } catch (_) {}
          },
        ),
        if (_volume > 1.0) ...[
          const SizedBox(height: 4),
          Text(
            'Gain above 100% may clip audio',
            style: TextStyle(
                fontSize: 11, fontFamily: theme.fontFamily, color: theme.muted),
          ),
        ],
        const SizedBox(height: 20),
        const SettingsSectionLabel('Input Level'),
        const SizedBox(height: 8),
        LevelMeter(level: _level),
        const SizedBox(height: 12),
        SettingsRow(
          label: 'Hear microphone',
          info: 'Plays this input through your default output, as others '
              'would hear it. Use headphones: through speakers it will feed '
              'back. Turns off when you leave this page.',
          control: _togglingMonitor
              ? const LoadingIndicator(size: 18)
              : SettingsToggle(
                  value: _monitorIndex != null,
                  onChanged: (_) => _toggleMonitor(),
                ),
        ),
        if (_monitorFailed)
          const SettingsHint(
              'Could not start the monitor: the sound server refused to '
              'load module-loopback.'),
        const SizedBox(height: 20),
        const SettingsSectionLabel('Noise Suppression'),
        const SizedBox(height: 8),
        if (!_noiseSuppAvailable)
          Text(
            'librnnoise_ladspa is not installed',
            style: TextStyle(
                fontSize: 13, fontFamily: theme.fontFamily, color: theme.muted),
          )
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enable noise suppression',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground),
                    ),
                    Text(
                      'Uses librnnoise_ladspa for voice denoising',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: theme.fontFamily,
                          color: theme.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _togglingNoiseSupp
                  ? const LoadingIndicator(size: 18)
                  // The handler flips from its own state, so the tapped-for
                  // value is ignored — same contract the old onTap had.
                  : SettingsToggle(
                      value: _noiseSuppEnabled,
                      onChanged: (_) => _toggleNoiseSupp(),
                    ),
            ],
          ),
      ],
    );
  }
}
