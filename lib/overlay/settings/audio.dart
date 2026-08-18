// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/pulse_client.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<bool> _isModuleLoaded(PulseClient client, String moduleName) async {
  try {
    final modules = await client.getModuleList();
    return modules.any((m) => m.name == moduleName);
  } catch (_) {
    return false;
  }
}

Future<int?> _findModuleIndex(PulseClient client, String moduleName) async {
  try {
    final modules = await client.getModuleList();
    for (final m in modules) {
      if (m.name == moduleName) return m.index;
    }
  } catch (_) {}
  return null;
}

class _DropdownItem<T> {
  const _DropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}

// ---------------------------------------------------------------------------
// _ActionButton
// ---------------------------------------------------------------------------

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool loading;

  @override
  _ActionButtonState createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final canTap = !widget.loading;
    final Color bg;
    if (widget.primary) {
      bg = _hovered && canTap
          ? theme.accent.withValues(alpha: 0.85)
          : theme.accent;
    } else {
      bg = _hovered && canTap ? theme.surfaceHover : theme.divider;
    }
    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canTap ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Center(
            child: widget.loading
                ? const LoadingIndicator(size: 14)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.primary
                          ? const Color(0xFFFFFFFF)
                          : theme.popupForeground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EnableToggle
// ---------------------------------------------------------------------------

class _EnableToggle extends StatefulWidget {
  const _EnableToggle({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  _EnableToggleState createState() => _EnableToggleState();
}

class _EnableToggleState extends State<_EnableToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = widget.enabled ? theme.accent : theme.divider;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered ? color.withValues(alpha: 0.8) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                left: widget.enabled ? 22 : 2,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OptionButton
// ---------------------------------------------------------------------------

class _OptionButton extends StatefulWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _OptionButtonState createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color bg;
    if (widget.selected) {
      bg = theme.accent;
    } else if (_hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = theme.controlSurface;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.selected ? theme.accent : theme.divider),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              color: widget.selected
                  ? const Color(0xFFFFFFFF)
                  : theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SectionLabel
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AudioTabBar + _AudioTabItem
// ---------------------------------------------------------------------------

class _AudioTabBar extends StatelessWidget {
  const _AudioTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++)
            _AudioTabItem(
              label: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onTabSelected(i),
            ),
        ],
      ),
    );
  }
}

class _AudioTabItem extends StatefulWidget {
  const _AudioTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _AudioTabItemState createState() => _AudioTabItemState();
}

class _AudioTabItemState extends State<_AudioTabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: widget.selected
                    ? theme.accent
                    : _hovered
                        ? theme.popupForeground
                        : theme.popupForeground.withValues(alpha: 0.6),
                fontWeight:
                    widget.selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AudioDropdown<T> — generic inline-expanding dropdown
// ---------------------------------------------------------------------------

class _AudioDropdown<T> extends StatefulWidget {
  // ignore: prefer_const_constructors_in_immutables
  _AudioDropdown({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<_DropdownItem<T>> items;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  _AudioDropdownState<T> createState() => _AudioDropdownState<T>();
}

class _AudioDropdownState<T> extends State<_AudioDropdown<T>> {
  bool _open = false;

  String get _selectedLabel {
    for (final item in widget.items) {
      if (item.value == widget.selected) return item.label;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DropdownTrigger(
          label: _selectedLabel,
          open: _open,
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: theme.controlSurface,
              border: Border.all(color: theme.divider),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.items.length,
              itemBuilder: (_, i) {
                final item = widget.items[i];
                final selected = item.value == widget.selected;
                return _DropdownListItem(
                  label: item.label,
                  selected: selected,
                  onTap: () {
                    widget.onSelected(item.value);
                    setState(() => _open = false);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DropdownTrigger extends StatefulWidget {
  const _DropdownTrigger({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  _DropdownTriggerState createState() => _DropdownTriggerState();
}

class _DropdownTriggerState extends State<_DropdownTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final bg =
        _hovered ? theme.surfaceHover : theme.controlSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FaIcon(
                widget.open
                    ? FontAwesomeIcons.chevronUp
                    : FontAwesomeIcons.chevronDown,
                size: 10,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownListItem extends StatefulWidget {
  const _DropdownListItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  _DropdownListItemState createState() => _DropdownListItemState();
}

class _DropdownListItemState extends State<_DropdownListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final bg = widget.selected
        ? theme.accent.withValues(alpha: 0.15)
        : _hovered
            ? theme.surfaceHover
            : const Color(0x00000000);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: bg,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontFamily: theme.fontFamily,
              color: widget.selected ? theme.accent : theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AudioSlider + _AudioSliderPainter
// ---------------------------------------------------------------------------

class _AudioSlider extends StatelessWidget {
  const _AudioSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.warningThreshold,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double min;
  final double max;
  final double? warningThreshold;
  final bool enabled;

  double _clampedFromGlobal(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final fraction = (local.dx / box.size.width).clamp(0.0, 1.0);
    return min + fraction * (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return GestureDetector(
      onHorizontalDragUpdate: enabled
          ? (d) => onChanged(_clampedFromGlobal(context, d.globalPosition))
          : null,
      onHorizontalDragEnd: enabled ? (_) => onChangeEnd(value) : null,
      onTapDown: enabled
          ? (d) {
              final v = _clampedFromGlobal(context, d.globalPosition);
              onChanged(v);
              onChangeEnd(v);
            }
          : null,
      child: CustomPaint(
        size: const Size(double.infinity, 20),
        painter: _AudioSliderPainter(
          value: value,
          min: min,
          max: max,
          warningThreshold: warningThreshold,
          enabled: enabled,
          trackColor: theme.sliderTrack,
          fillColor: theme.accent,
          thumbColor: theme.popupForeground,
        ),
      ),
    );
  }
}

class _AudioSliderPainter extends CustomPainter {
  const _AudioSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.trackColor,
    required this.fillColor,
    required this.thumbColor,
    this.warningThreshold,
  });

  final double value;
  final double min;
  final double max;
  final double? warningThreshold;
  final bool enabled;
  final Color trackColor;
  final Color fillColor;
  final Color thumbColor;

  static const _warningColor = Color(0xFFFF9500);

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    final range = max - min;
    final fraction = range > 0 ? ((value - min) / range).clamp(0.0, 1.0) : 0.0;
    final thumbX = fraction * size.width;

    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      Paint()
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    if (thumbX > 0) {
      final threshold = warningThreshold;
      if (threshold != null && enabled) {
        final thFraction = ((threshold - min) / range).clamp(0.0, 1.0);
        final thX = thFraction * size.width;
        if (thumbX <= thX) {
          canvas.drawLine(
              Offset(0, trackY),
              Offset(thumbX, trackY),
              Paint()
                ..color = fillColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
        } else {
          canvas.drawLine(
              Offset(0, trackY),
              Offset(thX, trackY),
              Paint()
                ..color = fillColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
          canvas.drawLine(
              Offset(thX, trackY),
              Offset(thumbX, trackY),
              Paint()
                ..color = _warningColor
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round);
        }
      } else {
        canvas.drawLine(
          Offset(0, trackY),
          Offset(thumbX, trackY),
          Paint()
            ..color = enabled ? fillColor : trackColor
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()..color = enabled ? thumbColor : trackColor,
    );
  }

  @override
  bool shouldRepaint(_AudioSliderPainter old) =>
      old.value != value ||
      old.min != min ||
      old.max != max ||
      old.enabled != enabled ||
      old.warningThreshold != warningThreshold ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.thumbColor != thumbColor;
}

// ---------------------------------------------------------------------------
// _LevelMeter
// ---------------------------------------------------------------------------

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SizedBox(
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          size: const Size(double.infinity, 8),
          painter: _LevelMeterPainter(
            level: level,
            trackColor: theme.sliderTrack,
            accentColor: theme.accent,
          ),
        ),
      ),
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  const _LevelMeterPainter({
    required this.level,
    required this.trackColor,
    required this.accentColor,
  });

  final double level;
  final Color trackColor;
  final Color accentColor;

  static const _orange = Color(0xFFFF9500);
  static const _red = Color(0xFFFF3333);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = trackColor);
    if (level <= 0) return;
    final fillW = (level * size.width).clamp(0.0, size.width);
    const z1 = 0.80, z2 = 0.95;
    final x1 = z1 * size.width;
    final x2 = z2 * size.width;
    if (fillW <= x1) {
      canvas.drawRect(Rect.fromLTWH(0, 0, fillW, size.height),
          Paint()..color = accentColor);
    } else if (fillW <= x2) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, x1, size.height), Paint()..color = accentColor);
      canvas.drawRect(Rect.fromLTWH(x1, 0, fillW - x1, size.height),
          Paint()..color = _orange);
    } else {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, x1, size.height), Paint()..color = accentColor);
      canvas.drawRect(
          Rect.fromLTWH(x1, 0, x2 - x1, size.height), Paint()..color = _orange);
      canvas.drawRect(
          Rect.fromLTWH(x2, 0, fillW - x2, size.height), Paint()..color = _red);
    }
  }

  @override
  bool shouldRepaint(_LevelMeterPainter old) =>
      old.level != level ||
      old.trackColor != trackColor ||
      old.accentColor != accentColor;
}

// ---------------------------------------------------------------------------
// AudioSettingsPage
// ---------------------------------------------------------------------------

class AudioSettingsPage extends StatefulWidget {
  const AudioSettingsPage({super.key});

  @override
  _AudioSettingsPageState createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  PulseClient? _client;
  bool _clientReady = false;
  String? _initError;
  int _selectedTab = 0;

  static const _tabs = ['Output', 'Input', 'Apps', 'Profiles', 'Advanced'];

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    try {
      final client = PulseClient();
      await client.initialize();
      if (!mounted) return;
      setState(() {
        _client = client;
        _clientReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'PulseAudio unavailable: $e');
    }
  }

  @override
  void dispose() {
    // PulseClient is a singleton — do not dispose here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_initError != null) return _buildError(theme);
    if (!_clientReady) return _buildLoading(theme);
    return _buildLoaded(theme);
  }

  Widget _buildHeader(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Text(
        'Audio',
        style: TextStyle(
          fontSize: 16,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        const Expanded(child: Center(child: LoadingIndicator(size: 22))),
      ],
    );
  }

  Widget _buildError(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Center(
            child: Text(
              _initError!,
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.accent),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoaded(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        _AudioTabBar(
          tabs: _tabs,
          selectedIndex: _selectedTab,
          onTabSelected: (i) => setState(() => _selectedTab = i),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabContent() {
    final client = _client!;
    switch (_selectedTab) {
      case 0:
        return _OutputTab(client: client);
      case 1:
        return _InputTab(client: client);
      case 2:
        return _AppsTab(client: client);
      case 3:
        return _ProfilesTab(client: client);
      case 4:
        return const _AdvancedTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Output Device
// ---------------------------------------------------------------------------

class _OutputTab extends StatefulWidget {
  const _OutputTab({required this.client});

  final PulseClient client;

  @override
  _OutputTabState createState() => _OutputTabState();
}

class _OutputTabState extends State<_OutputTab> {
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
      await Process.run(
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
              style: TextStyle(fontSize: 13, color: theme.accent),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: _ActionButton(
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
        .map((s) => _DropdownItem<String>(value: s.name, label: s.description))
        .toList();
    final volPct = (_volume * 100).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionLabel('Output Device'),
        const SizedBox(height: 8),
        _AudioDropdown<String>(
          items: items,
          selected: _defaultSinkName,
          onSelected: _selectSink,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const _SectionLabel('Volume'),
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _toggleMute,
                child: FaIcon(
                  _muted
                      ? FontAwesomeIcons.volumeXmark
                      : volPct == 0
                          ? FontAwesomeIcons.volumeOff
                          : volPct < 50
                              ? FontAwesomeIcons.volumeLow
                              : FontAwesomeIcons.volumeHigh,
                  size: 14,
                  color: _muted ? theme.muted : theme.popupForeground,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
        _AudioSlider(
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
          const _SectionLabel('Balance'),
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
                child: _AudioSlider(
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
        _ActionButton(
          label: 'Test Speakers',
          loading: _testingAudio,
          onTap: _testSpeakers,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Input Device
// ---------------------------------------------------------------------------

class _InputTab extends StatefulWidget {
  const _InputTab({required this.client});

  final PulseClient client;

  @override
  _InputTabState createState() => _InputTabState();
}

class _InputTabState extends State<_InputTab> {
  List<PaSource>? _sources;
  String _defaultSourceName = '';
  double _volume = 0.0;
  bool _muted = false;
  double _level = 0.0;
  bool _noiseSuppAvailable = false;
  bool _noiseSuppEnabled = false;
  bool _togglingNoiseSupp = false;
  bool _loading = true;
  String? _error;
  StreamSubscription<PaSource>? _sourceChangedSub;
  StreamSubscription<int>? _sourceRemovedSub;
  StreamSubscription<double>? _levelSub;

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
  }

  @override
  void dispose() {
    _sourceChangedSub?.cancel();
    _sourceRemovedSub?.cancel();
    _stopMeter();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final serverInfo = await widget.client.getServerInfo();
      final sources = await widget.client.getSourceList();
      final noiseSuppEnabled =
          await _isModuleLoaded(widget.client, 'module-ladspa-source');
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
      if (mounted) setState(() => _level = level);
    });
  }

  void _stopMeter() {
    _levelSub?.cancel();
    _levelSub = null;
    widget.client.stopLevelMeter();
    if (mounted) setState(() => _level = 0.0);
  }

  Future<void> _toggleNoiseSupp() async {
    if (_togglingNoiseSupp) return;
    setState(() => _togglingNoiseSupp = true);
    try {
      if (_noiseSuppEnabled) {
        final idx =
            await _findModuleIndex(widget.client, 'module-ladspa-source');
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
          await _isModuleLoaded(widget.client, 'module-ladspa-source');
      if (mounted) setState(() => _noiseSuppEnabled = enabled);
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
              style: TextStyle(fontSize: 13, color: theme.accent),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: _ActionButton(
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
        .map((s) => _DropdownItem<String>(value: s.name, label: s.description))
        .toList();
    final volPct = (_volume * 100).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionLabel('Input Device'),
        const SizedBox(height: 8),
        _AudioDropdown<String>(
          items: items,
          selected: _defaultSourceName,
          onSelected: _selectSource,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const _SectionLabel('Gain'),
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _toggleMute,
                child: FaIcon(
                  _muted
                      ? FontAwesomeIcons.microphoneSlash
                      : FontAwesomeIcons.microphone,
                  size: 14,
                  color: _muted ? theme.muted : theme.popupForeground,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
        _AudioSlider(
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
        const _SectionLabel('Input Level'),
        const SizedBox(height: 8),
        _LevelMeter(level: _level),
        const SizedBox(height: 20),
        const _SectionLabel('Noise Suppression'),
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
                  : _EnableToggle(
                      enabled: _noiseSuppEnabled,
                      onTap: _toggleNoiseSupp,
                    ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — Per-Application Volume
// ---------------------------------------------------------------------------

class _AppsTab extends StatefulWidget {
  const _AppsTab({required this.client});

  final PulseClient client;

  @override
  _AppsTabState createState() => _AppsTabState();
}

class _AppsTabState extends State<_AppsTab> {
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
              style: TextStyle(fontSize: 13, color: theme.accent),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: _ActionButton(
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
        .map((s) => _DropdownItem<String>(value: s.name, label: s.description))
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
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: FaIcon(
                    _muted
                        ? FontAwesomeIcons.volumeXmark
                        : FontAwesomeIcons.volumeLow,
                    size: 14,
                    color: _muted ? theme.muted : theme.popupForeground,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AudioSlider(
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
                child: _AudioDropdown<String>(
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

// ---------------------------------------------------------------------------
// Tab 4 — Device Profiles
// ---------------------------------------------------------------------------

class _ProfilesTab extends StatefulWidget {
  const _ProfilesTab({required this.client});

  final PulseClient client;

  @override
  _ProfilesTabState createState() => _ProfilesTabState();
}

class _ProfilesTabState extends State<_ProfilesTab> {
  List<PaCard>? _cards;
  String _defaultSinkName = '';
  bool _monoEnabled = false;
  bool _loading = true;
  String? _error;
  bool _togglingMono = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards = await widget.client.getCardList();
      final monoLoaded =
          await _isModuleLoaded(widget.client, 'module-remap-sink');
      final serverInfo = await widget.client.getServerInfo();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _monoEnabled = monoLoaded;
        _defaultSinkName = serverInfo.defaultSinkName;
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

  Future<void> _setProfile(PaCard card, String profileName) async {
    try {
      await widget.client.setCardProfile(card.name, profileName);
      await _load();
    } catch (_) {}
  }

  Future<void> _toggleMono() async {
    if (_togglingMono) return;
    setState(() => _togglingMono = true);
    try {
      if (_monoEnabled) {
        final idx = await _findModuleIndex(widget.client, 'module-remap-sink');
        if (idx != null) await widget.client.unloadModule(idx);
        if (_defaultSinkName.isNotEmpty) {
          await widget.client.setDefaultSink(_defaultSinkName);
        }
      } else {
        await widget.client.loadModule(
          'module-remap-sink',
          'sink_name=mono_mix'
              ' master=$_defaultSinkName'
              ' channels=1'
              ' channel_map=mono',
        );
        await widget.client.setDefaultSink('mono_mix');
      }
      final enabled = await _isModuleLoaded(widget.client, 'module-remap-sink');
      if (mounted) setState(() => _monoEnabled = enabled);
    } catch (_) {}
    if (mounted) setState(() => _togglingMono = false);
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
              style: TextStyle(fontSize: 13, color: theme.accent),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: _ActionButton(
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
    final cards = _cards!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: cards.isEmpty
              ? Center(
                  child: Text(
                    'No audio devices found',
                    style: TextStyle(
                        fontSize: 14,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProfileCard(
                    card: cards[i],
                    onProfileSelected: (p) => _setProfile(cards[i], p),
                  ),
                ),
        ),
        Container(height: 1, color: theme.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mono Audio',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground),
                    ),
                    Text(
                      'Mix all channels to a single channel',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: theme.fontFamily,
                          color: theme.muted),
                    ),
                  ],
                ),
              ),
              _togglingMono
                  ? const LoadingIndicator(size: 18)
                  : _EnableToggle(enabled: _monoEnabled, onTap: _toggleMono),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.card, required this.onProfileSelected});

  final PaCard card;
  final ValueChanged<String> onProfileSelected;

  @override
  _ProfileCardState createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late String _activeProfile;

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.card.activeProfileName;
  }

  @override
  void didUpdateWidget(_ProfileCard old) {
    super.didUpdateWidget(old);
    if (old.card.activeProfileName != widget.card.activeProfileName) {
      _activeProfile = widget.card.activeProfileName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final availableProfiles =
        widget.card.profiles.where((p) => p.available).toList();
    final profileItems = availableProfiles
        .map((p) => _DropdownItem<String>(value: p.name, label: p.description))
        .toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.description,
                  style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  widget.card.name,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.muted),
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.divider),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Profile',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 6),
                if (profileItems.isEmpty)
                  Text(
                    'No profiles available',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.muted),
                  )
                else
                  _AudioDropdown<String>(
                    items: profileItems,
                    selected: _activeProfile,
                    onSelected: (p) {
                      setState(() => _activeProfile = p);
                      widget.onProfileSelected(p);
                    },
                  ),
                if (widget.card.isBluez) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Bluetooth Codec',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Codec selection is managed by PipeWire/WirePlumber',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 5 — Advanced
// ---------------------------------------------------------------------------

class _AdvancedTab extends StatefulWidget {
  const _AdvancedTab();

  @override
  _AdvancedTabState createState() => _AdvancedTabState();
}

class _AdvancedTabState extends State<_AdvancedTab> {
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
      final result = await Process.run('pw-metadata', ['-n', 'settings', '0']);
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
      await Process.run(
          'pw-metadata', ['-n', 'settings', '0', 'clock.force-rate', '$rate']);
    } catch (_) {}
  }

  Future<void> _setQuantum(int q) async {
    setState(() => _quantum = q);
    try {
      await Process.run(
          'pw-metadata', ['-n', 'settings', '0', 'clock.force-quantum', '$q']);
    } catch (_) {}
  }

  void _startLogTail() async {
    try {
      _journalProcess = await Process.start('journalctl', [
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
      final result = await Process.run('systemctl',
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
        const _SectionLabel('PipeWire Settings'),
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
                .map((r) => _OptionButton(
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
                .map((q) => _OptionButton(
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
        const _SectionLabel('Audio Log'),
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
              child: _ActionButton(
                label: 'Restart Audio',
                onTap: _restartAudio,
                primary: true,
                loading: _restarting,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
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
