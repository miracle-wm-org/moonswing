import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/system/kill_confirm.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/process_killer.dart';
import 'package:graceful_shell/system/process_reader.dart';
import 'package:graceful_shell/system/system_stats_store.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/usage_bar.dart';

enum ProcessSortKey { name, pid, cpu, memory, uptime }

/// Every running process, sortable, filterable, and killable.
class ProcessTable extends StatefulWidget {
  const ProcessTable({super.key, required this.store});

  final SystemStatsStore store;

  @override
  State<ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<ProcessTable> {
  // Sort state is the table's, not the store's: which column a user is looking
  // at is a view concern, and the bar module's popup sorts differently.
  ProcessSortKey _sortKey = ProcessSortKey.cpu;
  bool _ascending = false;

  String _filter = '';
  int? _expandedPid;

  /// The process the confirmation card is asking about, if any.
  ProcessRow? _pendingKill;
  KillSeverity _pendingSeverity = KillSeverity.terminate;

  /// PIDs that have been sent a SIGTERM and have not exited yet. The value is
  /// the start time, so a PID recycled during the grace period is not mistaken
  /// for the original still refusing to die.
  final Map<int, int> _terminating = {};

  /// PIDs whose grace period has elapsed without them exiting — the rows that
  /// offer to force-quit.
  final Set<int> _unresponsive = {};

  final List<Timer> _graceTimers = [];

  ({KillOutcome outcome, String name, int pid})? _banner;

  @override
  void dispose() {
    for (final timer in _graceTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  // --- sorting -------------------------------------------------------------

  void _sortBy(ProcessSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        // Name and PID read naturally ascending; the numeric columns are asked
        // about in the "who is using the most" direction.
        _ascending = key == ProcessSortKey.name || key == ProcessSortKey.pid;
      }
    });
  }

  List<ProcessRow> _visibleRows() {
    final config = widget.store.config;
    final needle = _filter.trim().toLowerCase();

    final rows = widget.store.processes.where((p) {
      if (p.isKernelThread && !config.showKernelThreads) return false;
      if (needle.isEmpty) return true;
      return p.name.toLowerCase().contains(needle) ||
          p.cmdline.toLowerCase().contains(needle) ||
          '${p.pid}'.contains(needle);
    }).toList();

    rows.sort(_compare);
    return rows;
  }

  int _compare(ProcessRow a, ProcessRow b) {
    final int primary;
    switch (_sortKey) {
      case ProcessSortKey.name:
        primary = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case ProcessSortKey.pid:
        primary = a.pid.compareTo(b.pid);
      case ProcessSortKey.cpu:
        primary = a.cpuPercent.compareTo(b.cpuPercent);
      case ProcessSortKey.memory:
        primary = a.rssKb.compareTo(b.rssKb);
      case ProcessSortKey.uptime:
        primary = a.uptime.compareTo(b.uptime);
    }
    // PID breaks every tie. Rows arrive in readdir order and a screenful of
    // idle processes ties on CPU constantly; without a stable secondary key the
    // whole table reshuffles on every poll and cannot be read.
    final ordered = primary != 0 ? primary : a.pid.compareTo(b.pid);
    return _ascending ? ordered : -ordered;
  }

  // --- killing -------------------------------------------------------------

  void _requestKill(ProcessRow row) {
    final severity = _unresponsive.contains(row.pid)
        ? KillSeverity.force
        : KillSeverity.terminate;

    // A force-quit always confirms, whatever the config says: it is the one
    // that destroys unsaved work.
    if (!widget.store.config.confirmKill && severity == KillSeverity.terminate) {
      unawaited(_performKill(row, severity));
      return;
    }
    setState(() {
      _pendingKill = row;
      _pendingSeverity = severity;
    });
  }

  Future<void> _performKill(ProcessRow row, KillSeverity severity) async {
    setState(() => _pendingKill = null);

    final outcome = severity == KillSeverity.force
        ? await widget.store.forceKill(row)
        : await widget.store.terminate(row);
    if (!mounted) return;

    if (outcome != KillOutcome.signalled) {
      setState(() => _banner =
          (outcome: outcome, name: row.name, pid: row.pid));
      return;
    }

    if (severity == KillSeverity.force) {
      setState(() {
        _terminating.remove(row.pid);
        _unresponsive.remove(row.pid);
      });
      return;
    }

    setState(() => _terminating[row.pid] = row.starttimeTicks);

    // A SIGTERM is a request, and a well-behaved editor answers it by putting up
    // a save prompt. Escalating to SIGKILL automatically would then throw the
    // user's work away, so the grace period only *offers* the force-quit — it
    // never takes it.
    final grace = Duration(seconds: widget.store.config.killGraceSeconds);
    _graceTimers.add(Timer(grace, () {
      if (!mounted) return;
      if (!widget.store.isStillRunning(row)) {
        setState(() => _terminating.remove(row.pid));
        return;
      }
      setState(() => _unresponsive.add(row.pid));
    }));
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final rows = _visibleRows();
    final pending = _pendingKill;
    final banner = _banner;

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(theme, rows.length),
        if (banner != null)
          KillBanner(
            outcome: banner.outcome,
            processName: banner.name,
            pid: banner.pid,
            onDismiss: () => setState(() => _banner = null),
          ),
        Container(height: 1, color: theme.divider),
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    widget.store.processes.isEmpty
                        ? 'Reading processes…'
                        : 'No processes match “$_filter”',
                    style: TextStyle(
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _buildRow(theme, rows[i]),
                ),
        ),
      ],
    );

    if (pending == null) return table;

    return Stack(
      children: [
        table,
        KillConfirm(
          process: pending,
          severity: _pendingSeverity,
          onCancel: () => setState(() => _pendingKill = null),
          onConfirm: () => _performKill(pending, _pendingSeverity),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeConfig theme, int visible) {
    final total = widget.store.processes.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: SettingsTextField(
              initial: '',
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              total == 0
                  ? ''
                  : '$visible of $total processes · '
                      '${widget.store.threadCount} threads',
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _SortHeader(
              label: 'Name',
              sortKey: ProcessSortKey.name,
              active: _sortKey,
              ascending: _ascending,
              onTap: _sortBy,
            ),
          ),
          _headerCell(80, 'PID', ProcessSortKey.pid, TextAlign.right),
          _headerCell(124, 'CPU', ProcessSortKey.cpu, TextAlign.right),
          _headerCell(148, 'Memory', ProcessSortKey.memory, TextAlign.right),
          _headerCell(104, 'Uptime', ProcessSortKey.uptime, TextAlign.right),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _headerCell(
    double width,
    String label,
    ProcessSortKey key,
    TextAlign align,
  ) {
    return SizedBox(
      width: width,
      child: _SortHeader(
        label: label,
        sortKey: key,
        active: _sortKey,
        ascending: _ascending,
        align: align,
        onTap: _sortBy,
      ),
    );
  }

  Widget _buildRow(ThemeConfig theme, ProcessRow row) {
    return _ProcessRowTile(
      // Keyed on PID so a re-sort moves the row rather than recycling one
      // row's hover state onto a different process.
      key: ValueKey(row.pid),
      row: row,
      theme: theme,
      totalMemoryKb: widget.store.memory.totalKb,
      bootTime: widget.store.bootTime,
      expanded: _expandedPid == row.pid,
      terminating: _terminating.containsKey(row.pid),
      unresponsive: _unresponsive.contains(row.pid),
      onToggleExpand: () => setState(
        () => _expandedPid = _expandedPid == row.pid ? null : row.pid,
      ),
      onKill: () => _requestKill(row),
    );
  }
}

// ---------------------------------------------------------------------------
// Header cell
// ---------------------------------------------------------------------------

class _SortHeader extends StatefulWidget {
  const _SortHeader({
    required this.label,
    required this.sortKey,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.align = TextAlign.left,
  });

  final String label;
  final ProcessSortKey sortKey;
  final ProcessSortKey active;
  final bool ascending;
  final TextAlign align;
  final ValueChanged<ProcessSortKey> onTap;

  @override
  State<_SortHeader> createState() => _SortHeaderState();
}

class _SortHeaderState extends State<_SortHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isActive = widget.active == widget.sortKey;
    final color = isActive
        ? theme.accent
        : theme.popupForeground.withValues(alpha: _hovered ? 1.0 : 0.5);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.sortKey),
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: widget.align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                fontFamily: theme.fontFamily,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              FaIcon(
                widget.ascending
                    ? FontAwesomeIcons.caretUp
                    : FontAwesomeIcons.caretDown,
                size: 12,
                color: theme.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _ProcessRowTile extends StatefulWidget {
  const _ProcessRowTile({
    super.key,
    required this.row,
    required this.theme,
    required this.totalMemoryKb,
    required this.bootTime,
    required this.expanded,
    required this.terminating,
    required this.unresponsive,
    required this.onToggleExpand,
    required this.onKill,
  });

  final ProcessRow row;
  final ThemeConfig theme;
  final int totalMemoryKb;
  final DateTime? bootTime;
  final bool expanded;
  final bool terminating;
  final bool unresponsive;
  final VoidCallback onToggleExpand;
  final VoidCallback onKill;

  @override
  State<_ProcessRowTile> createState() => _ProcessRowTileState();
}

class _ProcessRowTileState extends State<_ProcessRowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final row = widget.row;

    final Color? background;
    if (_hovered || widget.expanded) {
      background = theme.popupForeground.withValues(alpha: 0.05);
    } else if (row.cpuPercent >= 50) {
      // A process eating the machine should be findable without sorting.
      background = theme.accent.withValues(alpha: 0.08);
    } else {
      background = null;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onToggleExpand,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Opacity(
                // A process that has been asked to quit is on its way out; dim
                // it so it stops competing for attention.
                opacity: widget.terminating && !widget.unresponsive ? 0.45 : 1,
                child: SizedBox(height: 34, child: _buildMainRow(theme, row)),
              ),
              if (widget.expanded) _buildDetail(theme, row),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainRow(ThemeConfig theme, ProcessRow row) {
    return Row(
      children: [
        Expanded(
          child: Text(
            row.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            '${row.pid}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.55),
            ),
          ),
        ),
        SizedBox(width: 124, child: _buildMeteredCell(
          theme,
          label: '${row.cpuPercent.toStringAsFixed(1)}%',
          fraction: row.cpuPercent / 100,
        )),
        SizedBox(width: 148, child: _buildMeteredCell(
          theme,
          label: formatBytesKb(row.rssKb),
          // Against total RAM, so the bar means the same thing in every row.
          fraction: widget.totalMemoryKb > 0
              ? row.rssKb / widget.totalMemoryKb
              : 0,
        )),
        SizedBox(
          width: 104,
          child: Text(
            formatUptime(row.uptime),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
        ),
        SizedBox(width: 40, child: _buildKillButton(theme)),
      ],
    );
  }

  Widget _buildMeteredCell(
    ThemeConfig theme, {
    required String label,
    required double fraction,
  }) {
    return Row(
      children: [
        Expanded(
          child: UsageBar(
            value: fraction,
            fillColor: theme.accent,
            trackColor: theme.sliderTrack,
            height: 6,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 68,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: ShellFontSizes.body,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKillButton(ThemeConfig theme) {
    if (widget.unresponsive) {
      return Align(
        alignment: Alignment.centerRight,
        child: SettingsIconButton(
          icon: FontAwesomeIcons.skull,
          size: 13,
          onTap: widget.onKill,
        ),
      );
    }

    // Hidden until the row is hovered. Four hundred always-visible X buttons
    // read as a wall of hazard, and make a mis-click likelier.
    return Opacity(
      opacity: _hovered ? 1 : 0,
      child: IgnorePointer(
        ignoring: !_hovered,
        child: Align(
          alignment: Alignment.centerRight,
          child: SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: 13,
            onTap: widget.onKill,
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(ThemeConfig theme, ProcessRow row) {
    final boot = widget.bootTime;
    final started =
        boot == null ? null : processStartTime(row.starttimeTicks, boot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.cmdline.isNotEmpty)
            Text(
              row.cmdline,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            [
              'Parent ${row.ppid}',
              'State ${_stateLabel(row.state)}',
              '${row.threads} ${row.threads == 1 ? 'thread' : 'threads'}',
              if (started != null) 'Started ${_formatClock(started)}',
            ].join('  ·  '),
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(String state) {
    switch (state) {
      case 'R':
        return 'running';
      case 'S':
        return 'sleeping';
      case 'D':
        return 'waiting on I/O';
      case 'Z':
        return 'zombie';
      case 'T':
        return 'stopped';
      case 'I':
        return 'idle';
      default:
        return state;
    }
  }

  static String _formatClock(DateTime t) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final time = '${two(t.hour)}:${two(t.minute)}';
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '$time today' : '${t.year}-${two(t.month)}-${two(t.day)} $time';
  }
}
