import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/system/disk_reader.dart';
import 'package:graceful_shell/system/history.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/proc_reader.dart';
import 'package:graceful_shell/system/process_killer.dart';
import 'package:graceful_shell/system/process_reader.dart';
import 'package:graceful_shell/system/process_sampler.dart';
import 'package:graceful_shell/system/system_monitor_config.dart';

/// The single source of system stats for the whole shell.
///
/// Same shape as [OsdStore] and [TrayStore]: a singleton [ChangeNotifier] that
/// a start-up function configures and the widgets watch.
///
/// **Leases, not timers.** Callers say what they need and for how long, and the
/// store polls only while somebody is listening:
///
///  * a *light* lease gets CPU, memory, temperature, load, and network — cheap
///    enough to read on the UI isolate. The bar module holds one for as long as
///    it is on a panel.
///  * a *detail* lease adds the per-process walk, which is expensive and runs
///    off-isolate. Only the process table takes one.
///
/// This is what keeps the overlay honest: [IndexedStack] keeps every tab alive
/// once built, so a tab that owned a `Timer` would keep walking `/proc` forever
/// while the user sat on Settings. Leasing ties the cost to visibility.
///
/// It also means there is exactly one sampler for the machine. Before this, a
/// two-monitor setup ran two independent timers each doing a full `/proc` walk.
///
/// A happy consequence: because the bar module holds a light lease from
/// start-up, [cpuHistory] is already full by the time anyone opens the monitor
/// tab, so the graphs draw populated instead of filling in over two minutes.
class SystemStatsStore extends ChangeNotifier {
  SystemStatsStore._({
    ProcReader? reader,
    ProcessSampler? sampler,
    DiskReader? disks,
    ProcessKiller? killer,
  })  : _reader = reader ?? ProcReader(),
        _sampler = sampler ?? IsolateProcessSampler(),
        _disks = disks ?? DiskReader(),
        _killer = killer ?? ProcessKiller();

  static final SystemStatsStore instance = SystemStatsStore._();

  @visibleForTesting
  factory SystemStatsStore.forTesting({
    required ProcReader reader,
    required ProcessSampler sampler,
    DiskReader? disks,
    ProcessKiller? killer,
    SystemMonitorConfig config = const SystemMonitorConfig(),
  }) {
    final store = SystemStatsStore._(
      reader: reader,
      sampler: sampler,
      disks: disks,
      killer: killer,
    );
    store.configure(config);
    return store;
  }

  final ProcReader _reader;
  final ProcessSampler _sampler;
  final DiskReader _disks;
  final ProcessKiller _killer;

  SystemMonitorConfig _config = const SystemMonitorConfig();
  SystemMonitorConfig get config => _config;

  // --- polling state -------------------------------------------------------

  Timer? _timer;
  int _lightLeases = 0;
  int _detailLeases = 0;

  /// Guards against a slow `/proc` under load queueing up walks behind each
  /// other: a tick that arrives while the previous one is still in flight is
  /// dropped, not deferred.
  bool _detailInFlight = false;

  DateTime? _lastDiskPoll;
  bool _diskInFlight = false;

  CpuSample? _prevCpu;
  NetSample? _prevNet;
  DateTime? _prevNetAt;
  Map<int, ProcessRaw> _prevProcesses = const {};

  /// A process's command line never changes, so it is read once and kept. The
  /// key is the PID; entries are dropped when the PID leaves the sample, and
  /// the start-time check in [computeProcessRows] catches the case where a PID
  /// is recycled before we notice.
  final Map<int, String> _cmdlineCache = {};

  // --- published state -----------------------------------------------------

  bool _hasData = false;

  /// False until the first poll completes. The bar module renders nothing
  /// rather than flashing zeroes.
  bool get hasData => _hasData;

  double _cpuPercent = 0;
  double get cpuPercent => _cpuPercent;

  List<CoreUsage> _cores = const [];
  List<CoreUsage> get cores => List.unmodifiable(_cores);

  MemorySample _memory = const MemorySample();
  MemorySample get memory => _memory;

  double? _temperatureCelsius;
  double? get temperatureCelsius => _temperatureCelsius;

  LoadAverage? _load;
  LoadAverage? get load => _load;

  Duration _uptime = Duration.zero;
  Duration get uptime => _uptime;

  DateTime? _bootTime;
  DateTime? get bootTime => _bootTime;

  String? _cpuModel;
  String? get cpuModel => _cpuModel;

  NetRate _netRate = NetRate.zero;
  NetRate get netRate => _netRate;

  List<DiskUsage> _diskUsage = const [];
  List<DiskUsage> get diskUsage => List.unmodifiable(_diskUsage);

  List<ProcessRow> _processes = const [];

  /// Every process, unsorted and unfiltered — the table owns those decisions.
  /// Empty until a detail lease has been held for one poll.
  List<ProcessRow> get processes => List.unmodifiable(_processes);

  int get threadCount =>
      _processes.fold(0, (sum, p) => sum + p.threads);

  final HistoryBuffer<HistorySample> _history = HistoryBuffer(120);

  /// The overview graphs' backing samples, oldest first.
  List<HistorySample> get history => _history.toList();
  int get historyCapacity => _history.capacity;

  // --- configuration -------------------------------------------------------

  void configure(SystemMonitorConfig config) {
    final cadenceChanged = config.pollSeconds != _config.pollSeconds;
    _config = config;
    _history.resize(config.historySamples);

    if (cadenceChanged && _timer != null) {
      _stopTimer();
      _startTimer();
    }
    notifyListeners();
  }

  // --- leases --------------------------------------------------------------

  /// Take a light lease. Cheap stats only; safe to hold for the life of a
  /// widget.
  void acquireLight() {
    _lightLeases++;
    if (_timer == null) _startTimer();
  }

  void releaseLight() {
    if (_lightLeases > 0) _lightLeases--;
    _stopTimerIfIdle();
  }

  /// Take a detail lease, adding the per-process walk. Released as soon as the
  /// process table stops being visible.
  void acquireDetail() {
    _detailLeases++;
    if (_timer == null) _startTimer();
    // Don't make the table wait a full poll interval to show anything.
    unawaited(_pollDetail());
  }

  void releaseDetail() {
    if (_detailLeases > 0) _detailLeases--;
    _stopTimerIfIdle();
  }

  void _startTimer() {
    // Seed the CPU baseline here rather than in a lease, so that whichever lease
    // happens to be first gets a real delta on the very next tick. Per-core
    // usage needs two samples to exist at all, so without this the tab could
    // open with an empty core grid.
    _prevCpu ??= _reader.readCpu();
    _timer = Timer.periodic(
      Duration(seconds: _config.pollSeconds),
      (_) => unawaited(_tick()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _stopTimerIfIdle() {
    if (_lightLeases == 0 && _detailLeases == 0) {
      _stopTimer();
      // The next lease starts from a clean baseline: a stale _prevCpu from
      // minutes ago would make the first delta an average over the whole gap.
      _prevCpu = null;
      _prevNet = null;
      _prevProcesses = const {};
    }
  }

  // --- polling -------------------------------------------------------------

  /// Whether a poll timer is running. Only a lease starts one.
  @visibleForTesting
  bool get isPolling => _timer != null;

  /// Runs one poll cycle to completion. Lets tests drive the store without
  /// waiting on real time.
  @visibleForTesting
  Future<void> tickForTesting() => _tick();

  Future<void> _tick() async {
    _pollLight();
    if (_detailLeases > 0) {
      await _pollDetail();
      await _pollDisksIfDue();
    }
  }

  void _pollLight() {
    final cpu = _reader.readCpu();
    final prevCpu = _prevCpu;
    if (cpu != null) {
      if (prevCpu != null) {
        _cpuPercent = CpuTimes.usageBetween(prevCpu.aggregate, cpu.aggregate);
        _cores = computeCoreUsage(prevCpu, cpu);
      }
      _bootTime = cpu.bootTime;
      _prevCpu = cpu;
    }

    _memory = _reader.readMemory();
    _temperatureCelsius = _reader.readTemperatureCelsius();
    _load = _reader.readLoad();
    _cpuModel ??= _reader.readCpuModel();

    final uptimeSeconds = _reader.readUptimeSeconds();
    if (uptimeSeconds != null) {
      _uptime = Duration(seconds: uptimeSeconds.round());
    }

    final now = DateTime.now();
    final net = _reader.readNet();
    if (net != null) {
      final prevNet = _prevNet;
      final prevAt = _prevNetAt;
      if (prevNet != null && prevAt != null) {
        _netRate = computeNetRate(prevNet, net, now.difference(prevAt));
      }
      _prevNet = net;
      _prevNetAt = now;
    }

    // Only record history once there is a real CPU delta to record; the first
    // poll after a lease has no baseline and would plant a 0% spike.
    if (prevCpu != null) {
      _history.add(HistorySample(
        cpuPercent: _cpuPercent,
        memoryFraction: _memory.usedFraction,
        swapFraction: _memory.swapUsedFraction,
        netRate: _netRate,
      ));
    }

    _hasData = true;
    notifyListeners();
  }

  Future<void> _pollDetail() async {
    if (_detailInFlight) return;
    _detailInFlight = true;
    try {
      final raw = await _sampler.sample(_cmdlineCache.keys.toSet());
      if (raw.isEmpty) return;

      final cpu = _prevCpu;
      final prevTotal = _prevProcessesTotalJiffies;
      final currentTotal = cpu?.aggregate.total ?? 0;

      for (final process in raw) {
        final cmdline = process.cmdline;
        if (cmdline != null) _cmdlineCache[process.pid] = cmdline;
      }

      _processes = computeProcessRows(
        current: raw,
        previous: _prevProcesses,
        deltaTotalJiffies: currentTotal - prevTotal,
        coreCount: cpu?.coreCount ?? 1,
        systemUptimeSeconds: _uptime.inMilliseconds / 1000,
        cmdlineCache: _cmdlineCache,
        mode: _config.cpuPercentMode,
      );

      _prevProcesses = {for (final p in raw) p.pid: p};
      _prevProcessesTotalJiffies = currentTotal;

      // Drop cache entries for processes that have exited, or the cache grows
      // without bound on a machine that churns short-lived processes.
      final live = _prevProcesses.keys.toSet();
      _cmdlineCache.removeWhere((pid, _) => !live.contains(pid));

      notifyListeners();
    } catch (e) {
      debugPrint('Process sampling failed: $e');
    } finally {
      _detailInFlight = false;
    }
  }

  /// The aggregate jiffy total at the time [_prevProcesses] was taken. Process
  /// CPU% is the process's tick delta over *this* delta, so the two must come
  /// from the same pair of moments.
  int _prevProcessesTotalJiffies = 0;

  Future<void> _pollDisksIfDue() async {
    if (_diskInFlight) return;
    final last = _lastDiskPoll;
    final due = last == null ||
        DateTime.now().difference(last).inSeconds >= _config.diskPollSeconds;
    if (!due) return;

    _diskInFlight = true;
    try {
      _diskUsage = await _disks.read();
      _lastDiskPoll = DateTime.now();
      notifyListeners();
    } finally {
      _diskInFlight = false;
    }
  }

  // --- killing -------------------------------------------------------------

  Future<KillOutcome> terminate(ProcessRow row) =>
      _killer.terminate(row.pid, expectedStarttimeTicks: row.starttimeTicks);

  Future<KillOutcome> forceKill(ProcessRow row) =>
      _killer.forceKill(row.pid, expectedStarttimeTicks: row.starttimeTicks);

  bool isStillRunning(ProcessRow row) =>
      _killer.isStillRunning(row.pid, row.starttimeTicks);

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

/// Configures [SystemStatsStore.instance] from the live config and keeps it in
/// step with edits made in the settings UI.
///
/// It deliberately does not start polling: the first lease does that, so a shell
/// with no system-monitor module on any panel and the tab unopened reads nothing
/// at all.
void startSystemStatsService() {
  final store = SystemStatsStore.instance;

  SystemMonitorConfig read() => SystemMonitorConfig.fromMap(
        ConfigStore.instance
            .get<Map<String, dynamic>>(['modules', 'system_monitor']),
      );

  store.configure(read());
  ConfigStore.instance.addListener(() => store.configure(read()));
}
