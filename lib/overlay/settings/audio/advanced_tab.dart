// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/host_process.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Tab 5 — Advanced
// ---------------------------------------------------------------------------

class AdvancedTab extends StatefulWidget {
  const AdvancedTab({super.key});

  @override
  _AdvancedTabState createState() => _AdvancedTabState();
}

class _AdvancedTabState extends State<AdvancedTab> {
  static const _sampleRates = [44100, 48000, 96000];
  static const _quanta = [32, 64, 128, 256, 512, 1024, 2048];

  int? _sampleRate;
  int? _quantum;
  bool _loadingSettings = true;
  String? _settingsError;
  final List<String> _logLines = [];
  Process? _journalProcess;
  StreamSubscription? _logSub;
  bool _restarting = false;
  String? _restartError;
  late final ScrollController _logScroll;

  @override
  void initState() {
    super.initState();
    _logScroll = ScrollController();
    _loadSettings();
    _startLogTail();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _journalProcess?.kill();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final result =
          await runHostProcess('pw-metadata', ['-n', 'settings', '0']);
      if (!mounted) return;
      final output = result.stdout as String;
      final rateMatch = RegExp(r"key:'clock\.(?:force-)?rate'\s+value:'(\d+)'")
          .firstMatch(output);
      final quantumMatch =
          RegExp(r"key:'clock\.quantum'\s+value:'(\d+)'").firstMatch(output);
      setState(() {
        _sampleRate = int.tryParse(rateMatch?.group(1) ?? '') ?? 48000;
        _quantum = int.tryParse(quantumMatch?.group(1) ?? '') ?? 1024;
        _loadingSettings = false;
        _settingsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSettings = false;
        _settingsError = 'pw-metadata not available';
      });
    }
  }

  Future<void> _setSampleRate(int rate) async {
    setState(() => _sampleRate = rate);
    try {
      await runHostProcess(
          'pw-metadata', ['-n', 'settings', '0', 'clock.force-rate', '$rate']);
    } catch (_) {}
  }

  Future<void> _setQuantum(int q) async {
    setState(() => _quantum = q);
    try {
      await runHostProcess(
          'pw-metadata', ['-n', 'settings', '0', 'clock.force-quantum', '$q']);
    } catch (_) {}
  }

  void _startLogTail() async {
    try {
      _journalProcess = await startHostProcess('journalctl', [
        '--user',
        '-u',
        'pipewire',
        '--output=cat',
        '-n',
        '50',
        '-f',
      ]);
      _logSub = _journalProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!mounted || line.trim().isEmpty) return;
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 200) _logLines.removeAt(0);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients &&
              _logScroll.position.hasContentDimensions) {
            _logScroll.animateTo(
              _logScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      });
      _journalProcess!.exitCode.then((_) => _journalProcess = null);
    } catch (_) {
      if (mounted) {
        setState(() => _logLines.add(
            'Log unavailable — journalctl not found or pipewire unit missing'));
      }
    }
  }

  Future<void> _restartAudio() async {
    if (_restarting) return;
    setState(() {
      _restarting = true;
      _restartError = null;
    });
    try {
      final result = await runHostProcess('systemctl',
          ['--user', 'restart', 'pipewire', 'pipewire-pulse', 'wireplumber']);
      if (result.exitCode != 0) throw Exception(result.stderr);
      await _loadSettings();
    } catch (e) {
      if (mounted) setState(() => _restartError = 'Restart failed: $e');
    }
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SettingsSectionLabel('PipeWire Settings'),
        const SizedBox(height: 12),
        if (_loadingSettings)
          const Center(child: LoadingIndicator(size: 18))
        else if (_settingsError != null)
          Text(_settingsError!,
              style: TextStyle(fontSize: 12, color: theme.accent))
        else ...[
          Text('Sample Rate',
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground)),
          const SizedBox(height: 2),
          Text('Requires audio restart to take full effect',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: theme.fontFamily,
                  color: theme.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sampleRates
                .map((r) => SettingsOptionButton(
                      label: '${r ~/ 1000} kHz',
                      selected: _sampleRate == r,
                      onTap: () => _setSampleRate(r),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('Buffer Size (quantum)',
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground)),
          const SizedBox(height: 2),
          Text('Current: ${_quantum ?? '—'} frames',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: theme.fontFamily,
                  color: theme.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quanta
                .map((q) => SettingsOptionButton(
                      label: '$q',
                      selected: _quantum == q,
                      onTap: () => _setQuantum(q),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        Container(height: 1, color: theme.divider),
        const SizedBox(height: 16),
        const SettingsSectionLabel('Audio Log'),
        const SizedBox(height: 8),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: theme.popupBackground.withValues(alpha: 0.5),
            border: Border.all(color: theme.divider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: _logLines.isEmpty
              ? Center(
                  child: Text(
                    'Waiting for log output…',
                    style: TextStyle(fontSize: 12, color: theme.muted),
                  ),
                )
              : ListView.builder(
                  controller: _logScroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: _logLines.length,
                  itemBuilder: (_, i) => Text(
                    _logLines[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: theme.popupForeground.withValues(alpha: 0.7),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: 'Restart Audio',
                onTap: _restartAudio,
                primary: true,
                loading: _restarting,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsActionButton(
                label: 'Clear Log',
                onTap: () => setState(() => _logLines.clear()),
              ),
            ),
          ],
        ),
        if (_restartError != null) ...[
          const SizedBox(height: 8),
          Text(_restartError!,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.accent)),
        ],
      ],
    );
  }
}
