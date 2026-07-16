import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/system/stat_tile.dart';
import 'package:graceful_shell/overlay/system/time_series_chart.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/system_stats_store.dart';
import 'package:graceful_shell/usage_bar.dart';

/// The machine at a glance: CPU with per-core breakdown, memory and swap,
/// vitals, network throughput, and filesystem usage.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.store});

  final SystemStatsStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final history = store.history;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCpuCard(context, theme, history),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildMemoryCard(context, theme, history)),
              const SizedBox(width: 12),
              SizedBox(width: 232, child: _buildVitalsCard(context)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildNetworkCard(context, theme, history)),
              const SizedBox(width: 12),
              Expanded(child: _buildDisksCard(context, theme)),
            ],
          ),
        ),
      ],
    );
  }

  // --- CPU -----------------------------------------------------------------

  Widget _buildCpuCard(
    BuildContext context,
    ThemeConfig theme,
    List<HistorySample> history,
  ) {
    final cores = store.cores;
    final model = store.cpuModel;

    return SystemCard(
      title: 'CPU',
      subtitle: model == null
          ? null
          : '$model · ${cores.length} ${cores.length == 1 ? 'thread' : 'threads'}',
      trailing: CardValue('${store.cpuPercent.toStringAsFixed(1)}%'),
      children: [
        TimeSeriesChart(
          series: [
            ChartSeries(
              values: [for (final h in history) h.cpuPercent],
              color: chartPrimary(theme),
            ),
          ],
          capacity: store.historyCapacity,
          height: 110,
        ),
        const SizedBox(height: 10),
        _buildCoreGrid(theme, cores),
      ],
    );
  }

  /// Cores laid out four to a row: sixteen threads is common, and a single
  /// column of sixteen bars would be taller than the whole panel.
  Widget _buildCoreGrid(ThemeConfig theme, List<CoreUsage> cores) {
    const columns = 4;
    final rows = <Widget>[];

    for (var start = 0; start < cores.length; start += columns) {
      final slice = cores.skip(start).take(columns).toList();
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: i < slice.length
                    ? _buildCoreCell(theme, slice[i])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _buildCoreCell(ThemeConfig theme, CoreUsage core) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            'CPU${core.index}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: UsageBar(
            value: core.percent / 100,
            fillColor: theme.accent,
            trackColor: theme.sliderTrack,
            height: 5,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${core.percent.round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  // --- Memory --------------------------------------------------------------

  Widget _buildMemoryCard(
    BuildContext context,
    ThemeConfig theme,
    List<HistorySample> history,
  ) {
    final memory = store.memory;

    return SystemCard(
      title: 'Memory',
      trailing: CardValue(
        '${formatBytesKb(memory.usedKb)} / ${formatBytesKb(memory.totalKb)}'
        '  (${(memory.usedFraction * 100).round()}%)',
      ),
      children: [
        TimeSeriesChart(
          series: [
            ChartSeries(
              values: [for (final h in history) h.memoryFraction * 100],
              color: chartSecondary(theme),
            ),
          ],
          capacity: store.historyCapacity,
          height: 90,
        ),
        const SizedBox(height: 10),
        _buildMemoryLine(
          theme,
          'Used',
          memory.usedFraction,
          formatBytesKb(memory.usedKb),
          chartSecondary(theme),
        ),
        _buildMemoryLine(
          theme,
          'Swap',
          memory.swapUsedFraction,
          memory.swapTotalKb == 0
              ? 'none'
              : '${formatBytesKb(memory.swapUsedKb)} / '
                  '${formatBytesKb(memory.swapTotalKb)}',
          chartTertiary(theme),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: StatLine(
                label: 'Cached',
                value: formatBytesKb(memory.cachedKb),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatLine(
                label: 'Free',
                value: formatBytesKb(memory.freeKb),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMemoryLine(
    ThemeConfig theme,
    String label,
    double fraction,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: UsageBar(
              value: fraction,
              fillColor: color,
              trackColor: theme.sliderTrack,
              height: 5,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Vitals --------------------------------------------------------------

  Widget _buildVitalsCard(BuildContext context) {
    final load = store.load;
    final temp = store.temperatureCelsius;
    final processes = store.processes;

    return SystemCard(
      title: 'Vitals',
      children: [
        StatLine(label: 'Uptime', value: formatUptime(store.uptime)),
        StatLine(
          label: 'Load avg',
          value: load == null
              ? '—'
              : '${load.one.toStringAsFixed(2)}  '
                  '${load.five.toStringAsFixed(2)}  '
                  '${load.fifteen.toStringAsFixed(2)}',
        ),
        StatLine(
          label: 'Temperature',
          value: temp == null
              ? '—'
              : formatTemperature(temp, store.config.tempUnit),
        ),
        StatLine(
          label: 'Processes',
          value: processes.isEmpty ? '—' : '${processes.length}',
        ),
        StatLine(
          label: 'Threads',
          value: processes.isEmpty ? '—' : '${store.threadCount}',
        ),
      ],
    );
  }

  // --- Network -------------------------------------------------------------

  Widget _buildNetworkCard(
    BuildContext context,
    ThemeConfig theme,
    List<HistorySample> history,
  ) {
    final rate = store.netRate;

    return SystemCard(
      title: 'Network',
      children: [
        Row(
          children: [
            FaIcon(FontAwesomeIcons.arrowDown,
                size: 10, color: chartPrimary(theme)),
            const SizedBox(width: 5),
            Text(
              formatRate(rate.rxBytesPerSecond),
              style: TextStyle(
                fontSize: 12,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground,
              ),
            ),
            const SizedBox(width: 16),
            FaIcon(FontAwesomeIcons.arrowUp,
                size: 10, color: chartSecondary(theme)),
            const SizedBox(width: 5),
            Text(
              formatRate(rate.txBytesPerSecond),
              style: TextStyle(
                fontSize: 12,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TimeSeriesChart(
          series: [
            ChartSeries(
              values: [for (final h in history) h.netRate.rxBytesPerSecond],
              color: chartPrimary(theme),
            ),
            ChartSeries(
              values: [for (final h in history) h.netRate.txBytesPerSecond],
              color: chartSecondary(theme),
            ),
          ],
          capacity: store.historyCapacity,
          // Throughput has no natural ceiling, so both series share an
          // autoscaled axis — that keeps rx and tx directly comparable.
          maxY: null,
          height: 70,
          gridDivisions: 3,
        ),
      ],
    );
  }

  // --- Disks ---------------------------------------------------------------

  Widget _buildDisksCard(BuildContext context, ThemeConfig theme) {
    final disks = store.diskUsage;

    return SystemCard(
      title: 'Disks',
      children: [
        if (disks.isEmpty)
          Text(
            'No filesystems reported',
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.5),
            ),
          )
        else
          for (final disk in disks) _buildDiskRow(theme, disk),
      ],
    );
  }

  Widget _buildDiskRow(ThemeConfig theme, DiskUsage disk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              disk.mountPoint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
          ),
          Expanded(
            child: UsageBar(
              value: disk.usedFraction,
              // A nearly-full disk is the one thing on this page that is
              // actionable, so it stops looking like every other bar.
              fillColor: disk.usedFraction > 0.9
                  ? const Color(0xFFE05252)
                  : theme.accent,
              trackColor: theme.sliderTrack,
              height: 5,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(
              '${formatBytes(disk.usedBytes)} / ${formatBytes(disk.totalBytes)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
