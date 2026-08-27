import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/underline_tabs.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/system_monitor_config.dart';
import 'package:graceful_shell/system/system_stats_store.dart';
import 'package:graceful_shell/usage_bar.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

/// CPU, memory, and temperature in the panel, with a popup breaking out the
/// per-core figures and the heaviest processes.
///
/// It reads nothing itself: [SystemStatsStore] does the sampling for the whole
/// shell, and this holds a lease on it for as long as it is mounted. Before that
/// existed, a two-monitor setup ran two independent `/proc` walks; now they
/// share one. For the full picture — graphs, sorting, killing — see the System
/// tab in the overlay.
class SystemMonitor extends StatefulWidget {
  const SystemMonitor({super.key});

  @override
  SystemMonitorState createState() => SystemMonitorState();
}

class SystemMonitorState extends State<SystemMonitor>
    with PopupHost<SystemMonitor> {
  final SystemStatsStore _store = SystemStatsStore.instance;

  @override
  void initState() {
    super.initState();
    _store.acquireLight();
  }

  @override
  void dispose() {
    _store.releaseLight();
    closePopup();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    final anchor = BarScope.of(context);
    final isVertical = anchor == 'left' || anchor == 'right';

    openBarPopup(
      context,
      preferredConstraints: isVertical
          ? const BoxConstraints.tightFor(width: 440, height: 420)
          : const BoxConstraints.tightFor(width: 420, height: 440),
      child: const ThemeProvider(child: _SystemMonitorPopup()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (!_store.hasData) return const SizedBox.shrink();

        final theme = ThemeScope.of(context);
        final tempC = _store.temperatureCelsius;

        return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.microchip,
                      size: 11, color: theme.foreground),
                  const SizedBox(width: 4),
                  Text(
                    '${_store.cpuPercent.round()}%',
                    style: TextStyle(fontSize: 12, color: theme.foreground),
                  ),
                  const SizedBox(width: 8),
                  FaIcon(FontAwesomeIcons.memory,
                      size: 11, color: theme.foreground),
                  const SizedBox(width: 4),
                  Text(
                    formatBytesKb(_store.memory.usedKb),
                    style: TextStyle(fontSize: 12, color: theme.foreground),
                  ),
                  if (tempC != null) ...[
                    const SizedBox(width: 8),
                    FaIcon(temperatureIcon(tempC),
                        size: 11, color: theme.foreground),
                    const SizedBox(width: 4),
                    Text(
                      formatTemperature(tempC, _store.config.tempUnit),
                      style: TextStyle(fontSize: 12, color: theme.foreground),
                    ),
                  ],
                ],
              ),
    );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Popup
// ---------------------------------------------------------------------------

enum _PopupTab { cpu, memory }

/// The popup's sub-tabs are denser than the overlay's, and that density is the
/// only thing that made them a hand-rolled clone of [UnderlineTab].
const double _kTabIconSize = 11;
const EdgeInsets _kTabPadding =
    EdgeInsets.symmetric(horizontal: 10, vertical: 8);

class _SystemMonitorPopup extends StatefulWidget {
  const _SystemMonitorPopup();

  @override
  State<_SystemMonitorPopup> createState() => _SystemMonitorPopupState();
}

class _SystemMonitorPopupState extends State<_SystemMonitorPopup> {
  final SystemStatsStore _store = SystemStatsStore.instance;
  _PopupTab _tab = _PopupTab.cpu;

  /// The process walk is expensive, so the popup only pays for it while the
  /// memory tab — the only thing that shows processes — is actually on screen.
  bool _holdingDetail = false;

  @override
  void dispose() {
    _releaseDetail();
    super.dispose();
  }

  void _selectTab(_PopupTab tab) {
    setState(() => _tab = tab);
    if (tab == _PopupTab.memory) {
      if (!_holdingDetail) {
        _holdingDetail = true;
        _store.acquireDetail();
      }
    } else {
      _releaseDetail();
    }
  }

  void _releaseDetail() {
    if (!_holdingDetail) return;
    _holdingDetail = false;
    _store.releaseDetail();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 12),
        child: PopupCard(
          // Clipped by default, and it earns it here: no padding, and the
          // tab bar, the divider and the charts all paint to their own edges.
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) => Column(
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
      ),
    );
  }

  Widget _buildTabBar(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          UnderlineTab(
            icon: FontAwesomeIcons.gaugeHigh,
            label: 'CPU',
            selected: _tab == _PopupTab.cpu,
            iconSize: _kTabIconSize,
            fontSize: ShellFontSizes.secondary,
            padding: _kTabPadding,
            onTap: () => _selectTab(_PopupTab.cpu),
          ),
          const SizedBox(width: 4),
          UnderlineTab(
            icon: FontAwesomeIcons.server,
            label: 'Memory',
            selected: _tab == _PopupTab.memory,
            iconSize: _kTabIconSize,
            fontSize: ShellFontSizes.secondary,
            padding: _kTabPadding,
            onTap: () => _selectTab(_PopupTab.memory),
          ),
        ],
      ),
    );
  }

  Widget _buildCpuTab(ThemeConfig theme) {
    final cores = _store.cores;
    if (cores.isEmpty) {
      return Center(
        child: Text('No CPU data',
            style:
                TextStyle(color: theme.popupForeground.withValues(alpha: 0.5))),
      );
    }

    final tempC = _store.temperatureCelsius;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        if (tempC != null) ...[
          Row(
            children: [
              FaIcon(temperatureIcon(tempC),
                  size: 11,
                  color: theme.popupForeground.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('Temperature',
                  style: TextStyle(
                      color: theme.popupForeground.withValues(alpha: 0.7),
                      fontSize: 11)),
              const Spacer(),
              Text(formatTemperature(tempC, _store.config.tempUnit),
                  style: TextStyle(color: theme.popupForeground, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: theme.divider),
          const SizedBox(height: 8),
        ],
        for (final core in cores) _buildCoreRow(core, theme),
      ],
    );
  }

  Widget _buildCoreRow(CoreUsage core, ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              'CPU${core.index}',
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.7),
                  fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: UsageBar(
              value: core.percent / 100,
              fillColor: theme.accent,
              trackColor: theme.sliderTrack,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${core.percent.round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(color: theme.popupForeground, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              formatUptime(core.busyTime),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.59),
                  fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryTab(ThemeConfig theme) {
    final memory = _store.memory;
    final processes = _store.processes.where((p) => p.rssKb > 0).toList()
      ..sort((a, b) => b.rssKb.compareTo(a.rssKb));
    final top = processes.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              FaIcon(FontAwesomeIcons.memory,
                  size: 11,
                  color: theme.popupForeground.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('System Memory',
                  style: TextStyle(
                      color: theme.popupForeground.withValues(alpha: 0.7),
                      fontSize: 11)),
              const Spacer(),
              Text(
                  '${formatBytesKb(memory.usedKb)} / '
                  '${formatBytesKb(memory.totalKb)}',
                  style: TextStyle(color: theme.popupForeground, fontSize: 12)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: UsageBar(
            value: memory.usedFraction,
            fillColor: theme.accent,
            trackColor: theme.sliderTrack,
            height: 4,
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: top.isEmpty
              ? Center(
                  child: Text('Loading...',
                      style: TextStyle(
                          color: theme.popupForeground.withValues(alpha: 0.5))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: top.length,
                  itemBuilder: (context, i) => _buildProcessRow(
                    top[i],
                    memory.totalKb.toDouble(),
                    theme,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildProcessRow(ProcessRow proc, double totalKb, ThemeConfig theme) {
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
            child: UsageBar(
              // Against total RAM, not against the largest process: normalising
              // to the biggest row makes whatever is at the top always look
              // like it has eaten the machine.
              value: totalKb > 0 ? proc.rssKb / totalKb : 0,
              fillColor: theme.accent,
              trackColor: theme.sliderTrack,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              formatBytesKb(proc.rssKb),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: theme.popupForeground.withValues(alpha: 0.78),
                  fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Module registration
// ---------------------------------------------------------------------------

final Module systemMonitorModule = Module.simple<SystemMonitorConfig>(
  configKey: 'system_monitor',
  fromMap: (map) {
    final config = SystemMonitorConfig.fromMap(map);
    // The store, not the widget, owns the config: the overlay's System tab
    // reads the same settings and must see them even when no panel carries
    // this module.
    SystemStatsStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const SystemMonitor(),
);
