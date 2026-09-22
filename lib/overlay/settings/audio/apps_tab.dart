// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/pulse_client.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/audio/audio_slider.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// Tab 3 — Per-Application Volume
// ---------------------------------------------------------------------------

class AppsTab extends StatefulWidget {
  const AppsTab({super.key, required this.client});

  final PulseClient client;

  @override
  _AppsTabState createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  List<PaSinkInput>? _sinkInputs;
  List<PaSink>? _sinks;
  bool _loading = true;
  String? _error;
  StreamSubscription<PaSink>? _sinkChangedSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _sinkChangedSub = widget.client.onSinkChanged.listen((_) => _load());
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final inputs = await widget.client.getSinkInputList();
      final sinks = await widget.client.getSinkList();
      if (!mounted) return;
      setState(() {
        _sinkInputs = inputs;
        _sinks = sinks;
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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_error != null) return _buildRetry(theme, _error!);
    if (_loading) return const Center(child: LoadingIndicator(size: 22));
    final inputs = _sinkInputs!;
    final sinks = _sinks!;
    if (inputs.isEmpty) {
      return Center(
        child: Text(
          'No applications playing audio',
          style: TextStyle(
              fontSize: 14,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.5)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: inputs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _SinkInputItem(client: widget.client, input: inputs[i], sinks: sinks),
    );
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
}

class _SinkInputItem extends StatefulWidget {
  const _SinkInputItem(
      {required this.client, required this.input, required this.sinks});

  final PulseClient client;
  final PaSinkInput input;
  final List<PaSink> sinks;

  @override
  _SinkInputItemState createState() => _SinkInputItemState();
}

class _SinkInputItemState extends State<_SinkInputItem> {
  late double _volume;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _volume = widget.input.volume;
    _muted = widget.input.mute;
  }

  @override
  void didUpdateWidget(_SinkInputItem old) {
    super.didUpdateWidget(old);
    if (old.input.index != widget.input.index) {
      _volume = widget.input.volume;
      _muted = widget.input.mute;
    }
  }

  Future<void> _setVolume(double v) async {
    setState(() => _volume = v);
    try {
      await widget.client.setSinkInputVolume(widget.input.index, v);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final newMuted = !_muted;
    setState(() => _muted = newMuted);
    try {
      await widget.client.setSinkInputMute(widget.input.index, newMuted);
    } catch (_) {}
  }

  Future<void> _moveTo(String sinkName) async {
    try {
      await widget.client.moveSinkInput(widget.input.index, sinkName);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final label = widget.input.appName == widget.input.mediaName
        ? widget.input.appName
        : '${widget.input.appName} — ${widget.input.mediaName}';

    final sinkItems = widget.sinks
        .map((s) => SettingsDropdownItem<String>(value: s.name, label: s.description))
        .toList();
    final currentSink = widget.sinks
        .where((s) => s.index == widget.input.sinkIndex)
        .firstOrNull;
    final currentSinkName = currentSink?.name ??
        (sinkItems.isNotEmpty ? sinkItems.first.value : '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(FontAwesomeIcons.music,
                  size: 12,
                  color: theme.popupForeground.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.input.corked)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: theme.divider,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    'Paused',
                    style: TextStyle(
                        fontSize: 10,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SettingsIconButton(
                icon: _muted
                    ? FontAwesomeIcons.volumeXmark
                    : FontAwesomeIcons.volumeLow,
                size: ShellFontSizes.label,
                color: _muted ? theme.muted : theme.popupForeground,
                onTap: _toggleMute,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: AudioSlider(
                  value: _volume,
                  min: 0.0,
                  max: 1.5,
                  enabled: !_muted,
                  onChanged: (v) => setState(() => _volume = v),
                  onChangeEnd: _setVolume,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(_volume * 100).round()}%',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Output: ',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.6)),
              ),
              Expanded(
                child: SettingsDropdown<String>(
                  items: sinkItems,
                  selected: currentSinkName,
                  onSelected: _moveTo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
