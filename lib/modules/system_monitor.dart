// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_positioner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/layer_shell.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class SystemMonitorConfig {
  final int pollSeconds;
  final String tempUnit; // 'celsius' | 'fahrenheit'

  const SystemMonitorConfig({
    this.pollSeconds = 2,
    this.tempUnit = 'celsius',
  });

  factory SystemMonitorConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SystemMonitorConfig();
    return SystemMonitorConfig(
      pollSeconds: map['poll_seconds'] as int? ?? 2,
      tempUnit: map['temp_unit'] as String? ?? 'celsius',
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _CpuCoreStat {
  final int user;
  final int nice;
  final int system;
  final int idle;
  final int total;

  const _CpuCoreStat({
    required this.user,
    required this.nice,
    required this.system,
    required this.idle,
    required this.total,
  });
}

class _CpuCoreInfo {
  final int index;
  final double usagePercent;
  final Duration totalTime; // accumulated user+nice+system time

  const _CpuCoreInfo({
    required this.index,
    required this.usagePercent,
    required this.totalTime,
  });
}

class _ProcessInfo {
  final String name;
  final int rssKb;

  const _ProcessInfo({required this.name, required this.rssKb});
}

// ---------------------------------------------------------------------------
// System reading utilities
// ---------------------------------------------------------------------------

/// Reads per-core CPU stats from /proc/stat.
/// Returns a list where index 0 = core 0, index 1 = core 1, etc.
List<_CpuCoreStat> _readCpuStats() {
  final file = File('/proc/stat');
  if (!file.existsSync()) return [];

  final lines = file.readAsLinesSync();
  final stats = <_CpuCoreStat>[];

  for (final line in lines) {
    if (!line.startsWith('cpu') || line.startsWith('cpu ')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 5) continue;

    final user = int.tryParse(parts[1]) ?? 0;
    final nice = int.tryParse(parts[2]) ?? 0;
    final system = int.tryParse(parts[3]) ?? 0;
    final idle = int.tryParse(parts[4]) ?? 0;
    final iowait = parts.length > 5 ? (int.tryParse(parts[5]) ?? 0) : 0;
    final irq = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
    final softirq = parts.length > 7 ? (int.tryParse(parts[7]) ?? 0) : 0;

    final total = user + nice + system + idle + iowait + irq + softirq;
    stats.add(_CpuCoreStat(
      user: user,
      nice: nice,
      system: system,
      idle: idle,
      total: total,
    ));
  }
  return stats;
}

/// Computes per-core info by diffing two snapshots.
List<_CpuCoreInfo> _computeCpuInfo(
  List<_CpuCoreStat> prev,
  List<_CpuCoreStat> curr,
) {
  final result = <_CpuCoreInfo>[];
  for (int i = 0; i < curr.length && i < prev.length; i++) {
    final deltaTotal = curr[i].total - prev[i].total;
    final deltaIdle = curr[i].idle - prev[i].idle;
    final usage =
        deltaTotal > 0 ? (deltaTotal - deltaIdle) / deltaTotal * 100 : 0.0;

    // Accumulated CPU time since boot: (user + nice + system) / USER_HZ
    const userHz = 100;
    final totalSeconds =
        (curr[i].user + curr[i].nice + curr[i].system) ~/ userHz;
    final duration = Duration(seconds: totalSeconds);

    result.add(_CpuCoreInfo(
      index: i,
      usagePercent: usage.clamp(0.0, 100.0),
      totalTime: duration,
    ));
  }
  return result;
}

/// Returns total CPU usage % (average across cores) from a diff.
double _computeTotalCpuUsage(
  List<_CpuCoreStat> prev,
  List<_CpuCoreStat> curr,
) {
  if (curr.isEmpty || prev.isEmpty) return 0.0;
  // Use aggregate first reading from /proc/stat (the "cpu " line is excluded
  // since we only parse "cpuN" lines). Sum all deltas instead.
  double totalUsage = 0.0;
  int count = 0;
  for (int i = 0; i < curr.length && i < prev.length; i++) {
    final deltaTotal = curr[i].total - prev[i].total;
    final deltaIdle = curr[i].idle - prev[i].idle;
    if (deltaTotal > 0) {
      totalUsage += (deltaTotal - deltaIdle) / deltaTotal * 100;
      count++;
    }
  }
  return count > 0 ? totalUsage / count : 0.0;
}

/// Reads /proc/meminfo and returns (usedKb, totalKb).
(int usedKb, int totalKb) _readMemInfo() {
  final file = File('/proc/meminfo');
  if (!file.existsSync()) return (0, 0);

  int totalKb = 0;
  int availableKb = 0;

  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('MemTotal:')) {
      totalKb = _parseMemInfoLine(line);
    } else if (line.startsWith('MemAvailable:')) {
      availableKb = _parseMemInfoLine(line);
    }
  }
  return (totalKb - availableKb, totalKb);
}

int _parseMemInfoLine(String line) {
  final parts = line.split(RegExp(r'\s+'));
  return parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
}

/// Returns top processes sorted by RSS descending.
List<_ProcessInfo> _readProcesses({int limit = 20}) {
  final procDir = Directory('/proc');
  if (!procDir.existsSync()) return [];

  final processes = <_ProcessInfo>[];

  for (final entry in procDir.listSync()) {
    if (entry is! Directory) continue;
    final pid = int.tryParse(entry.path.split('/').last);
    if (pid == null) continue;

    try {
      final statusFile = File('${entry.path}/status');
      if (!statusFile.existsSync()) continue;

      String name = '';
      int rssKb = 0;

      for (final line in statusFile.readAsLinesSync()) {
        if (line.startsWith('Name:')) {
          name = line.substring(5).trim();
        } else if (line.startsWith('VmRSS:')) {
          rssKb = _parseMemInfoLine(line);
        }
      }

      if (name.isNotEmpty && rssKb > 0) {
        processes.add(_ProcessInfo(name: name, rssKb: rssKb));
      }
    } catch (_) {
      // Process may have exited; skip
    }
  }

  processes.sort((a, b) => b.rssKb.compareTo(a.rssKb));
  return processes.take(limit).toList();
}

/// Reads the first usable thermal zone temperature in milli-Celsius.
/// Returns null if no temperature sensor is found.
double? _readTemperatureCelsius() {
  final thermalDir = Directory('/sys/class/thermal');
  if (!thermalDir.existsSync()) return null;

  final zones = thermalDir
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.split('/').last.startsWith('thermal_zone'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Prefer zones whose type contains meaningful CPU-related keywords
  Directory? preferred;
  Directory? fallback;

  for (final zone in zones) {
    final typeFile = File('${zone.path}/type');
    if (!typeFile.existsSync()) continue;

    final type = typeFile.readAsStringSync().trim().toLowerCase();
    final tempFile = File('${zone.path}/temp');
    if (!tempFile.existsSync()) continue;

    if (type.contains('pkg') ||
        type.contains('cpu') ||
        type.contains('x86') ||
        type.contains('core')) {
      preferred = zone;
      break;
    }
    fallback ??= zone;
  }

  final zone = preferred ?? fallback;
  if (zone == null) return null;

  try {
    final milliCelsius =
        int.tryParse(File('${zone.path}/temp').readAsStringSync().trim());
    if (milliCelsius == null) return null;
    return milliCelsius / 1000.0;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _formatBytes(int kb) {
  if (kb >= 1024 * 1024) {
    return '${(kb / 1024 / 1024).toStringAsFixed(1)}G';
  } else if (kb >= 1024) {
    return '${(kb / 1024).toStringAsFixed(1)}M';
  }
  return '${kb}K';
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

FaIconData _temperatureIcon(double celsius) {
  if (celsius >= 80) return FontAwesomeIcons.temperatureHigh;
  if (celsius <= 30) return FontAwesomeIcons.temperatureLow;
  return FontAwesomeIcons.temperatureHalf;
}

// ---------------------------------------------------------------------------
// Bar widget
// ---------------------------------------------------------------------------

class SystemMonitor extends StatefulWidget {
  const SystemMonitor({super.key, required this.config});

  final SystemMonitorConfig config;

  @override
  SystemMonitorState createState() => SystemMonitorState();
}

class SystemMonitorState extends State<SystemMonitor> {
  Timer? _timer;

  // Bar display state
  double _cpuPercent = 0.0;
  int _memUsedKb = 0;
  int _memTotalKb = 0;
  double? _tempCelsius;
  bool _hasData = false;

  // CPU delta tracking
  List<_CpuCoreStat> _prevCpuStats = [];
  List<_CpuCoreInfo> _coreInfo = [];

  // Popup state
  PopupWindowController? _popupController;
  PopupWindow? _popupView;
  bool _hovered = false;
  bool _popupHasBeenActive = false;

  @override
  void initState() {
    super.initState();
    // Seed the first snapshot so the first delta is valid
    _prevCpuStats = _readCpuStats();
    _timer = Timer.periodic(
      Duration(seconds: widget.config.pollSeconds),
      (_) => _poll(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _closePopup();
    super.dispose();
  }

  void _poll() {
    try {
      final currStats = _readCpuStats();
      final cores = _computeCpuInfo(_prevCpuStats, currStats);
      final cpuPercent = _computeTotalCpuUsage(_prevCpuStats, currStats);
      _prevCpuStats = currStats;

      final (usedKb, totalKb) = _readMemInfo();
      final temp = _readTemperatureCelsius();

      if (!mounted) return;
      setState(() {
        _cpuPercent = cpuPercent;
        _memUsedKb = usedKb;
        _memTotalKb = totalKb;
        _tempCelsius = temp;
        _coreInfo = cores;
        _hasData = true;
      });
    } catch (_) {
      // Silently fail
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
        anchorRect =
            Rect.fromLTWH(0, offset.dy, barLogicalWidth, size.height);
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

    final theme = ThemeScope.of(context);
    final isVertical = anchor == 'left' || anchor == 'right';

    PopupWindowController? thisController;
    _popupController = thisController = PopupWindowController(
      parent: parentController,
      anchorRect: anchorRect,
      positioner: WindowPositioner(
        parentAnchor: parentAnchor,
        childAnchor: childAnchor,
      ),
      preferredConstraints: isVertical
          ? const BoxConstraints.tightFor(width: 440, height: 420)
          : const BoxConstraints.tightFor(width: 420, height: 440),
      delegate: _SystemMonitorPopupDelegate(onDestroyed: () {
        if (_popupController == thisController) _closePopup();
      }),
    );

    _popupView = PopupWindow(
      controller: _popupController!,
      child: ThemeScope(
        theme: theme,
        child: _SystemMonitorPopup(
          config: widget.config,
          initialCoreInfo: _coreInfo,
          initialPrevStats: _prevCpuStats,
          memUsedKb: _memUsedKb,
          memTotalKb: _memTotalKb,
          tempCelsius: _tempCelsius,
        ),
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ctrl.isDestroyed) ctrl.destroy();
      });
    }
    if (mounted) setState(() {});
  }

  String _formatTemp(double celsius) {
    if (widget.config.tempUnit == 'fahrenheit') {
      final f = celsius * 9 / 5 + 32;
      return '${f.round()}°F';
    }
    return '${celsius.round()}°C';
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) return const SizedBox.shrink();

    final theme = ThemeScope.of(context);
    final isActive = _hovered || _popupController != null;

    final tempC = _tempCelsius;

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
              FaIcon(FontAwesomeIcons.microchip,
                  size: 11, color: theme.foreground),
              const SizedBox(width: 4),
              Text(
                '${_cpuPercent.round()}%',
                style: TextStyle(fontSize: 12, color: theme.foreground),
              ),
              const SizedBox(width: 8),
              FaIcon(FontAwesomeIcons.memory, size: 11, color: theme.foreground),
              const SizedBox(width: 4),
              Text(
                _formatBytes(_memUsedKb),
                style: TextStyle(fontSize: 12, color: theme.foreground),
              ),
              if (tempC != null) ...[
                const SizedBox(width: 8),
                FaIcon(_temperatureIcon(tempC),
                    size: 11, color: theme.foreground),
                const SizedBox(width: 4),
                Text(
                  _formatTemp(tempC),
                  style: TextStyle(fontSize: 12, color: theme.foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Popup delegate
// ---------------------------------------------------------------------------

class _SystemMonitorPopupDelegate extends PopupWindowControllerDelegate {
  _SystemMonitorPopupDelegate({required this.onDestroyed});
  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    onDestroyed();
  }
}

// ---------------------------------------------------------------------------
// Popup widget
// ---------------------------------------------------------------------------

enum _PopupTab { cpu, memory }

class _SystemMonitorPopup extends StatefulWidget {
  const _SystemMonitorPopup({
    required this.config,
    required this.initialCoreInfo,
    required this.initialPrevStats,
    required this.memUsedKb,
    required this.memTotalKb,
    required this.tempCelsius,
  });

  final SystemMonitorConfig config;
  final List<_CpuCoreInfo> initialCoreInfo;
  final List<_CpuCoreStat> initialPrevStats;
  final int memUsedKb;
  final int memTotalKb;
  final double? tempCelsius;

  @override
  _SystemMonitorPopupState createState() => _SystemMonitorPopupState();
}

class _SystemMonitorPopupState extends State<_SystemMonitorPopup> {
  _PopupTab _tab = _PopupTab.cpu;
  Timer? _timer;

  List<_CpuCoreInfo> _coreInfo = [];
  List<_CpuCoreStat> _prevStats = [];
  List<_ProcessInfo> _processes = [];
  int _memUsedKb = 0;
  int _memTotalKb = 0;
  double? _tempCelsius;

  @override
  void initState() {
    super.initState();
    _coreInfo = widget.initialCoreInfo;
    _prevStats = widget.initialPrevStats;
    _memUsedKb = widget.memUsedKb;
    _memTotalKb = widget.memTotalKb;
    _tempCelsius = widget.tempCelsius;

    // Load processes immediately for memory tab
    _refreshProcesses();

    _timer = Timer.periodic(
      Duration(seconds: widget.config.pollSeconds),
      (_) => _poll(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    try {
      final curr = _readCpuStats();
      final cores = _computeCpuInfo(_prevStats, curr);
      _prevStats = curr;

      final (usedKb, totalKb) = _readMemInfo();
      final temp = _readTemperatureCelsius();

      if (_tab == _PopupTab.memory) {
        _refreshProcesses();
      }

      if (!mounted) return;
      setState(() {
        _coreInfo = cores;
        _memUsedKb = usedKb;
        _memTotalKb = totalKb;
        _tempCelsius = temp;
      });
    } catch (_) {}
  }

  void _refreshProcesses() {
    try {
      final procs = _readProcesses();
      if (mounted) {
        setState(() => _processes = procs);
      } else {
        _processes = procs;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 12),
        child: Container(
          color: theme.popupBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabBar(theme),
              Container(height: 1, color: theme.divider),
              Expanded(
                child: _tab == _PopupTab.cpu
                    ? _buildCpuTab(theme)
                    : _buildMemoryTab(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: Row(
        children: [
          _TabButton(
            icon: FontAwesomeIcons.gaugeHigh,
            label: 'CPU',
            selected: _tab == _PopupTab.cpu,
            theme: theme,
            onTap: () => setState(() => _tab = _PopupTab.cpu),
          ),
          const SizedBox(width: 4),
          _TabButton(
            icon: FontAwesomeIcons.server,
            label: 'Memory',
            selected: _tab == _PopupTab.memory,
            theme: theme,
            onTap: () {
              setState(() => _tab = _PopupTab.memory);
              _refreshProcesses();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCpuTab(ThemeConfig theme) {
    if (_coreInfo.isEmpty) {
      return Center(
        child: Text('No CPU data',
            style: TextStyle(color: theme.popupForeground.withValues(alpha: 0.5))),
      );
    }

    final tempC = _tempCelsius;
    final String? tempLabel = tempC != null
        ? widget.config.tempUnit == 'fahrenheit'
            ? '${(tempC * 9 / 5 + 32).round()}°F'
            : '${tempC.round()}°C'
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        if (tempLabel != null) ...[
          Row(
            children: [
              FaIcon(_temperatureIcon(tempC!),
                  size: 11, color: theme.popupForeground.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('Temperature',
                  style: TextStyle(
                      color: theme.popupForeground.withValues(alpha: 0.7),
                      fontSize: 11)),
              const Spacer(),
              Text(tempLabel,
                  style:
                      TextStyle(color: theme.popupForeground, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: theme.divider),
          const SizedBox(height: 8),
        ],
        for (final core in _coreInfo) _buildCoreRow(core, theme),
      ],
    );
  }

  Widget _buildCoreRow(_CpuCoreInfo core, ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              'CPU${core.index}',
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.7), fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _UsageBar(
              value: core.usagePercent / 100,
              fillColor: theme.accent,
              trackColor: theme.sliderTrack,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${core.usagePercent.round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: theme.popupForeground, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              _formatDuration(core.totalTime),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.59), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryTab(ThemeConfig theme) {
    final usedLabel = _formatBytes(_memUsedKb);
    final totalLabel = _formatBytes(_memTotalKb);

    final maxRss =
        _processes.isNotEmpty ? _processes.first.rssKb.toDouble() : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              FaIcon(FontAwesomeIcons.memory,
                  size: 11, color: theme.popupForeground.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('System Memory',
                  style: TextStyle(
                      color: theme.popupForeground.withValues(alpha: 0.7),
                      fontSize: 11)),
              const Spacer(),
              Text('$usedLabel / $totalLabel',
                  style:
                      TextStyle(color: theme.popupForeground, fontSize: 12)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: _UsageBar(
            value: _memTotalKb > 0 ? _memUsedKb / _memTotalKb : 0,
            fillColor: theme.accent,
            trackColor: theme.sliderTrack,
            height: 4,
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: _processes.isEmpty
              ? Center(
                  child: Text('Loading...',
                      style: TextStyle(
                          color: theme.popupForeground.withValues(alpha: 0.5))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: _processes.length,
                  itemBuilder: (context, i) =>
                      _buildProcessRow(_processes[i], maxRss, theme),
                ),
        ),
      ],
    );
  }

  Widget _buildProcessRow(
      _ProcessInfo proc, double maxRss, ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              proc.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.popupForeground, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _UsageBar(
              value: maxRss > 0 ? proc.rssKb / maxRss : 0,
              fillColor: theme.accent,
              trackColor: theme.sliderTrack,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              _formatBytes(proc.rssKb),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.78), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab button
// ---------------------------------------------------------------------------

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool selected;
  final ThemeConfig theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? theme.accent : theme.popupForeground.withValues(alpha: 0.63);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? theme.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 11, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Usage bar painter
// ---------------------------------------------------------------------------

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.value,
    required this.fillColor,
    required this.trackColor,
    this.height = 6,
  });

  final double value;
  final Color fillColor;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _UsageBarPainter(
            value: value.clamp(0.0, 1.0),
            fillColor: fillColor,
            trackColor: trackColor,
          ),
        );
      },
    );
  }
}

class _UsageBarPainter extends CustomPainter {
  const _UsageBarPainter({
    required this.value,
    required this.fillColor,
    required this.trackColor,
  });

  final double value;
  final Color fillColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(3);
    final trackRect =
        Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = trackColor,
    );
    if (value > 0) {
      final fillRect =
          Rect.fromLTWH(0, 0, size.width * value, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        Paint()..color = fillColor,
      );
    }
  }

  @override
  bool shouldRepaint(_UsageBarPainter old) =>
      old.value != value ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}

// ---------------------------------------------------------------------------
// Module registration
// ---------------------------------------------------------------------------

class SystemMonitorModule extends Module {
  SystemMonitorConfig _config = const SystemMonitorConfig();

  @override
  String get configKey => 'system_monitor';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = SystemMonitorConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder =>
      (context) => SystemMonitor(config: _config);
}
