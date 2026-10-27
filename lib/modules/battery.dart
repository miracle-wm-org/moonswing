import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config_reader.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/native/udev_monitor.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

class BatteryConfig {
  final int pollSeconds;

  const BatteryConfig({this.pollSeconds = 30});

  factory BatteryConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BatteryConfig();
    return BatteryConfig(
      pollSeconds: map.intOr('poll_seconds', 30),
    );
  }
}

/// One reading of the pack, as the bar renders it.
///
/// The store publishes this rather than the line of text it used to compose,
/// so the glyph is the widget's decision and the arithmetic is the store's —
/// and so a reading can be compared: `==` is what lets a poll that found
/// nothing new stay silent (see [BatteryStore._readBattery]). It carries only
/// what the bar draws; the estimate and everything else is [BatteryDetails],
/// which the popup reads, so a moving estimate wakes no bar.
@immutable
class BatteryReading {
  const BatteryReading({
    required this.capacity,
    required this.charging,
  });

  /// Charge across every battery in the machine, 0-100.
  final int capacity;

  /// On mains and filling — not merely "not discharging", which is what a
  /// laptop sitting at 100% on the charger reports.
  final bool charging;

  @override
  bool operator ==(Object other) =>
      other is BatteryReading &&
      other.capacity == capacity &&
      other.charging == charging;

  @override
  int get hashCode => Object.hash(capacity, charging);
}

/// The glyph for [reading], from the icon font the shell already ships.
///
/// Charging is the plug, which is what the emoji before it said. Anything else
/// is the level itself: the one battery emoji was the same picture for a full
/// pack and a dying one, and five steps is what an icon set can say instead.
ShellGlyph batteryIconFor(BatteryReading reading) {
  if (reading.charging) return ShellGlyph.plug;
  if (reading.capacity >= 90) return ShellGlyph.batteryFull;
  if (reading.capacity >= 65) return ShellGlyph.batteryThreeQuarters;
  if (reading.capacity >= 40) return ShellGlyph.batteryHalf;
  if (reading.capacity >= 15) return ShellGlyph.batteryQuarter;
  return ShellGlyph.batteryEmpty;
}

/// The text beside [batteryIconFor]'s glyph: the level and nothing else. The
/// estimate is the popup's, where it has room to say which way it runs.
String batteryLabelFor(BatteryReading reading) => '${reading.capacity}%';

// ---------------------------------------------------------------------------
// The packs, read and summed
// ---------------------------------------------------------------------------

/// What the packs are doing together.
enum BatteryChargeState {
  charging('Charging'),
  discharging('Discharging'),
  full('Fully charged'),
  notCharging('Plugged in, not charging');

  const BatteryChargeState(this.label);

  final String label;
}

/// One pack's `/sys/class/power_supply/<name>` files, read once.
///
/// Every file degrades on its own: a driver that does not publish a rate or a
/// cycle count costs that row of the popup, never the reading.
@immutable
class BatterySample {
  const BatterySample({
    required this.name,
    this.status = '',
    this.now,
    this.full,
    this.fullDesign,
    this.rate,
    this.voltage,
    this.energyBased = true,
    this.cycleCount,
    this.manufacturer,
    this.model,
    this.technology,
  });

  /// Reads the pack at [path]. Energy files (µWh, µW) first, charge files
  /// (µAh, µA) where a driver has only those.
  factory BatterySample.read(String path) {
    String? text(String file) {
      try {
        final value = File('$path/$file').readAsStringSync().trim();
        return value.isEmpty ? null : value;
      } catch (_) {
        return null;
      }
    }

    int? number(String file) {
      final value = text(file);
      return value == null ? null : int.tryParse(value);
    }

    final energyNow = number('energy_now');
    final energyFull = number('energy_full');
    final energyBased = energyNow != null && energyFull != null;
    return BatterySample(
      name: path.split('/').last,
      status: text('status') ?? '',
      now: energyBased ? energyNow : number('charge_now'),
      full: energyBased ? energyFull : number('charge_full'),
      fullDesign:
          number(energyBased ? 'energy_full_design' : 'charge_full_design'),
      rate: number(energyBased ? 'power_now' : 'current_now'),
      voltage: number('voltage_now'),
      energyBased: energyBased,
      cycleCount: number('cycle_count'),
      manufacturer: text('manufacturer'),
      model: text('model_name'),
      technology: text('technology'),
    );
  }

  /// The directory name: `BAT0`, `BAT1`, `CMB0`.
  final String name;

  /// `Charging`, `Discharging`, `Full`, `Not charging` or `Unknown`.
  final String status;

  /// µWh, or µAh where [energyBased] is false.
  final int? now;
  final int? full;
  final int? fullDesign;

  /// µW, or µA where [energyBased] is false. Taken as a magnitude: some
  /// drivers sign it negative while discharging and some never do, and
  /// [status] already says which way it runs.
  final int? rate;

  /// µV, which is what turns a current into watts.
  final int? voltage;

  final bool energyBased;
  final int? cycleCount;
  final String? manufacturer;
  final String? model;
  final String? technology;

  int? get _rate => rate?.abs();

  /// Watts in or out of this pack, or null where the driver gives no rate (or,
  /// for a charge-based one, no voltage to multiply it by).
  double? get watts {
    final rate = _rate;
    if (rate == null) return null;
    if (energyBased) return rate / 1e6;
    final voltage = this.voltage;
    if (voltage == null) return null;
    return rate * voltage / 1e12;
  }
}

/// One pack as the popup lists it.
@immutable
class BatteryPackInfo {
  const BatteryPackInfo({
    required this.name,
    this.capacity,
    this.health,
    this.cycles,
    this.model,
    this.technology,
  });

  final String name;

  /// This pack's own charge, 0-100.
  final int? capacity;

  /// What the pack holds when full against what it was built to, as a
  /// percentage — wear. Not clamped: a new pack can read above 100, and that
  /// is what its firmware says.
  final int? health;

  /// Charge cycles, where the firmware counts them (0 is how most say they
  /// do not, so it is read as absent).
  final int? cycles;

  /// Manufacturer and model, as the firmware names them.
  final String? model;

  /// `Li-ion`, `Li-poly`, … ; never `Unknown`.
  final String? technology;

  @override
  bool operator ==(Object other) =>
      other is BatteryPackInfo &&
      other.name == name &&
      other.capacity == capacity &&
      other.health == health &&
      other.cycles == cycles &&
      other.model == model &&
      other.technology == technology;

  @override
  int get hashCode =>
      Object.hash(name, capacity, health, cycles, model, technology);
}

/// Everything the popup renders, and nothing it does not: `==` is what keeps
/// a poll that changed only a figure the popup rounds away silent.
@immutable
class BatteryDetails {
  const BatteryDetails({
    required this.reading,
    required this.state,
    this.timeLeft,
    this.watts,
    this.packs = const [],
  });

  final BatteryReading reading;
  final BatteryChargeState state;

  /// Until full while charging, until empty while discharging; null while
  /// idle, and null rather than a figure the estimate cannot support.
  final Duration? timeLeft;

  /// Watts across every pack, to a tenth, while charging or discharging.
  final double? watts;

  final List<BatteryPackInfo> packs;

  @override
  bool operator ==(Object other) =>
      other is BatteryDetails &&
      other.reading == reading &&
      other.state == state &&
      other.timeLeft == timeLeft &&
      other.watts == watts &&
      listEquals(other.packs, packs);

  @override
  int get hashCode =>
      Object.hash(reading, state, timeLeft, watts, Object.hashAll(packs));
}

int? _percent(int? part, int? whole) {
  if (part == null || whole == null || whole <= 0) return null;
  return (part * 100 / whole).round();
}

/// Sums [samples] into the bar's reading and the popup's details.
({BatteryReading reading, BatteryDetails details}) summariseBatteries(
  List<BatterySample> samples,
) {
  var totalNow = 0;
  var totalFull = 0;
  var totalRate = 0;
  double? totalWatts;
  var anyCharging = false;
  var anyDischarging = false;
  var allFull = samples.isNotEmpty;

  for (final sample in samples) {
    if (sample.status == 'Charging') anyCharging = true;
    if (sample.status == 'Discharging') anyDischarging = true;
    if (sample.status != 'Full') allFull = false;
    totalNow += sample.now ?? 0;
    totalFull += sample.full ?? 0;
    totalRate += sample._rate ?? 0;
    final watts = sample.watts;
    if (watts != null) totalWatts = (totalWatts ?? 0) + watts;
  }

  final charging = anyCharging && !anyDischarging;
  final state = anyDischarging
      ? BatteryChargeState.discharging
      : charging
          ? BatteryChargeState.charging
          : allFull
              ? BatteryChargeState.full
              : BatteryChargeState.notCharging;
  final reading = BatteryReading(
    capacity: _percent(totalNow, totalFull) ?? 0,
    charging: charging,
  );

  final moving =
      state == BatteryChargeState.charging ||
      state == BatteryChargeState.discharging;
  Duration? timeLeft;
  if (moving && totalRate > 0) {
    final hours = charging
        ? (totalFull - totalNow) / totalRate
        : totalNow / totalRate;
    if (hours >= 0 && hours <= 100) {
      timeLeft = Duration(minutes: (hours * 60).round());
    }
  }

  final details = BatteryDetails(
    reading: reading,
    state: state,
    timeLeft: timeLeft,
    watts: moving && totalWatts != null && totalWatts > 0
        ? (totalWatts * 10).round() / 10
        : null,
    packs: [
      for (final sample in samples)
        BatteryPackInfo(
          name: sample.name,
          capacity: _percent(sample.now, sample.full),
          health: _percent(sample.full, sample.fullDesign),
          cycles: (sample.cycleCount ?? 0) > 0 ? sample.cycleCount : null,
          model: [sample.manufacturer, sample.model]
              .whereType<String>()
              .join(' ')
              .nullIfEmpty,
          technology:
              sample.technology == 'Unknown' ? null : sample.technology,
        ),
    ],
  );
  return (reading: reading, details: details);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// `2 h 05 min`, or `45 min` under the hour.
String formatBatteryDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours == 0) return '$minutes min';
  return '$hours h ${minutes.toString().padLeft(2, '0')} min';
}

/// The line under the popup's percentage: the state, then the estimate in the
/// direction it runs, where there is one.
String batteryStatusLine(BatteryDetails details) {
  final time = details.timeLeft;
  if (time == null) return details.state.label;
  final estimate = formatBatteryDuration(time);
  return details.state == BatteryChargeState.charging
      ? '${details.state.label} · $estimate until full'
      : '${details.state.label} · $estimate remaining';
}

/// One row of the popup's table: a label and its value, or a heading naming
/// the pack the rows under it describe.
@immutable
class BatteryDetailRow {
  const BatteryDetailRow(this.label, this.value);

  const BatteryDetailRow.heading(this.label) : value = null;

  final String label;

  /// Null for a heading.
  final String? value;

  bool get isHeading => value == null;

  @override
  bool operator ==(Object other) =>
      other is BatteryDetailRow && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => isHeading ? '# $label' : '$label: $value';
}

/// The popup's table for [details]. One pack is described without a heading;
/// several each get one, with their own charge, since the percentage above the
/// table is all of them together.
List<BatteryDetailRow> batteryDetailRows(BatteryDetails details) {
  final watts = details.watts;
  final several = details.packs.length > 1;
  return [
    if (watts != null)
      BatteryDetailRow(
        details.state == BatteryChargeState.charging
            ? 'Charging at'
            : 'Power draw',
        '${watts.toStringAsFixed(1)} W',
      ),
    for (final pack in details.packs) ...[
      if (several) BatteryDetailRow.heading(pack.name),
      if (several && pack.capacity != null)
        BatteryDetailRow('Charge', '${pack.capacity}%'),
      if (pack.health != null) BatteryDetailRow('Health', '${pack.health}%'),
      if (pack.cycles != null) BatteryDetailRow('Cycles', '${pack.cycles}'),
      if (pack.technology != null)
        BatteryDetailRow('Technology', pack.technology!),
      if (pack.model != null) BatteryDetailRow('Model', pack.model!),
    ],
  ];
}

// ---------------------------------------------------------------------------
// The store
// ---------------------------------------------------------------------------

/// [BatteryStore.detailChanges]: a notifier the store can fire from outside
/// `ChangeNotifier`'s own protected API.
class _DetailSignal extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// The battery reading for the whole shell.
///
/// The singleton-`ChangeNotifier` shape with `SystemStatsStore`'s lease rule: the
/// store reads `/sys/class/power_supply` and holds the udev subscription only
/// while at least one widget holds a lease. A two-monitor setup used to run one
/// timer and one udev watch per bar.
///
/// Two tiers. A bar's lease publishes [reading] at `poll_seconds`; an open
/// popup's *detail* lease adds [details] — the estimate, the draw, each pack's
/// health — on a faster poll of its own, since a draw read every thirty seconds
/// is no answer to "what is this costing me now". Each tier notifies through
/// its own listenable, so the popup's churn wakes no bar.
class BatteryStore extends ChangeNotifier {
  BatteryStore._({
    required String sysfsRoot,
    required bool watchUdev,
  })  : _sysfsRoot = sysfsRoot,
        _watchUdev = watchUdev;

  static final BatteryStore instance = BatteryStore._(
    sysfsRoot: '/sys/class/power_supply',
    watchUdev: true,
  );

  @visibleForTesting
  factory BatteryStore.forTesting({
    BatteryConfig config = const BatteryConfig(),
    String sysfsRoot = '/sys/class/power_supply',
  }) {
    final store = BatteryStore._(sysfsRoot: sysfsRoot, watchUdev: false);
    store.configure(config);
    return store;
  }

  final String _sysfsRoot;
  final bool _watchUdev;

  /// The detail tier's cadence.
  static const Duration detailPoll = Duration(seconds: 5);

  BatteryConfig _config = const BatteryConfig();

  /// Applies [config]; the module's `fromMap` pushes it here. A cadence change
  /// while leased restarts the timer at the new interval.
  void configure(BatteryConfig config) {
    final cadenceChanged = config.pollSeconds != _config.pollSeconds;
    _config = config;
    if (cadenceChanged && _timer != null) {
      _stopTimer();
      _startTimer();
    }
  }

  // --- published state -----------------------------------------------------

  BatteryReading? _reading;

  /// The last reading, or null until the first one lands.
  BatteryReading? get reading => _reading;

  bool _hasBattery = false;
  bool get hasBattery => _hasBattery;

  BatteryDetails? _details;

  /// The popup's reading, or null while no detail lease is held.
  BatteryDetails? get details => _details;

  final _DetailSignal _detailSignal = _DetailSignal();

  /// Fires when [details] changes; [BatteryStore] itself fires only for
  /// [reading].
  Listenable get detailChanges => _detailSignal;

  // --- polling state -------------------------------------------------------

  int _leases = 0;
  Timer? _timer;
  UdevMonitor? _udev;

  int _detailLeases = 0;
  Timer? _detailTimer;

  /// Battery paths never change while the shell runs (a hotplugged battery is
  /// a laptop being reassembled), so detection runs once, on the first lease
  /// ever — re-running it would duplicate the paths.
  bool _detected = false;
  final List<String> _batteryPaths = [];

  /// Take a lease. The first active lease detects batteries, starts the udev
  /// watch, starts polling, and reads immediately so the bar never waits a
  /// full interval for its first reading.
  void acquire() {
    _leases++;
    if (_timer != null) return;
    _detect();
    if (_hasBattery && _watchUdev) _monitorPowerSupply();
    _startTimer();
    _readBattery();
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases == 0) {
      _stopTimer();
      _udev?.dispose();
      _udev = null;
    }
  }

  /// Take a detail lease — an open popup's. The first one reads at once so the
  /// popup's first frame has something in it, and does so **without
  /// notifying**: it runs inside the popup's `initState`, mid-build.
  void acquireDetail() {
    _detailLeases++;
    if (_detailTimer != null) return;
    _detect();
    _detailTimer = Timer.periodic(detailPoll, (_) => _readBattery());
    _readBattery(notify: false);
  }

  void releaseDetail() {
    if (_detailLeases > 0) _detailLeases--;
    if (_detailLeases > 0) return;
    _detailTimer?.cancel();
    _detailTimer = null;
    _details = null;
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(seconds: _config.pollSeconds),
      (_) => _readBattery(),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _detect() {
    if (_detected) return;
    _detected = true;
    try {
      final dir = Directory(_sysfsRoot);
      if (!dir.existsSync()) return;

      for (final entry in dir.listSync()) {
        final typeFile = File('${entry.path}/type');
        if (typeFile.existsSync()) {
          final type = typeFile.readAsStringSync().trim();
          if (type == 'Battery') {
            _batteryPaths.add(entry.path);
          }
        }
      }
      // Sorted, so BAT0 is listed before BAT1 whatever order the directory
      // listing came back in.
      _batteryPaths.sort();

      _hasBattery = _batteryPaths.isNotEmpty;
    } catch (_) {
      // No battery available
    }
  }

  void _monitorPowerSupply() {
    if (_udev != null) return;
    try {
      _udev = UdevMonitor(subsystems: ['power_supply'], onEvent: _readBattery);
    } catch (_) {
      // udev monitoring unavailable, fall back to polling only
    }
  }

  /// Reads every pack. With [notify] false only [details] is taken — silently
  /// — and a changed [reading] is left for the next read to notice, so nothing
  /// the bars listen to moves without telling them.
  void _readBattery({bool notify = true}) {
    if (_batteryPaths.isEmpty) return;

    final summary = summariseBatteries([
      for (final path in _batteryPaths) BatterySample.read(path),
    ]);

    if (_detailLeases > 0 && summary.details != _details) {
      _details = summary.details;
      if (notify) _detailSignal.changed();
    }

    // Every bar on every monitor listens, and udev speaks up for any change
    // in the subsystem — a charger's own current included. A reading that
    // renders identically is not news.
    if (!notify || summary.reading == _reading) return;
    _reading = summary.reading;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    _detailTimer?.cancel();
    _udev?.dispose();
    _detailSignal.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// The bar button
// ---------------------------------------------------------------------------

class Battery extends StatefulWidget {
  const Battery({super.key});

  @override
  BatteryState createState() => BatteryState();
}

class BatteryState extends State<Battery> with PopupHost<Battery> {
  final BatteryStore _store = BatteryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.acquire();
  }

  @override
  void dispose() {
    closePopup();
    _store.release();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
      child: ThemeProvider(child: BatteryPopup(store: _store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final reading = _store.reading;
        if (!_store.hasBattery || reading == null) {
          return const SizedBox.shrink();
        }

        final theme = ThemeScope.of(context);
        return BarButton(
          active: isPopupOpen,
          onTapDown: (_) => _togglePopup(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShellIcon(
                batteryIconFor(reading),
                size: 12,
                color: theme.foreground,
              ),
              const SizedBox(width: 4),
              Text(
                batteryLabelFor(reading),
                style: TextStyle(fontSize: 16, color: theme.foreground),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The popup
// ---------------------------------------------------------------------------

/// The level, what the packs are doing and for how long, and a table of the
/// rest. Holds the store's detail lease for as long as it is open.
class BatteryPopup extends StatefulWidget {
  const BatteryPopup({super.key, required this.store});

  final BatteryStore store;

  @override
  State<BatteryPopup> createState() => _BatteryPopupState();
}

class _BatteryPopupState extends State<BatteryPopup> {
  @override
  void initState() {
    super.initState();
    widget.store.acquireDetail();
  }

  @override
  void dispose() {
    widget.store.releaseDetail();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // [ShellTextRoot], not a bare [DefaultTextStyle]: popup content is laid
    // out directly under its own FlutterView, with no [Directionality] above.
    return ShellTextRoot(
      style: TextStyle(
        color: theme.popupForeground,
        fontSize: ShellFontSizes.secondary,
      ),
      child: PopupCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ListenableBuilder(
          listenable: widget.store.detailChanges,
          builder: (context, _) {
            final details = widget.store.details;
            if (details == null) {
              return Text(
                'No battery found',
                style: TextStyle(color: theme.muted),
              );
            }
            final rows = batteryDetailRows(details);
            return Column(
              mainAxisSize: MainAxisSize.min,
              // `start`, never `stretch`: the popup surface is sized to its
              // content, and a stretched column reports the constraints' width.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BatteryHeader(details: details),
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _BatteryTable(rows: rows),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BatteryHeader extends StatelessWidget {
  const _BatteryHeader({required this.details});

  final BatteryDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShellIcon(
          batteryIconFor(details.reading),
          size: ShellFontSizes.heading,
          color: theme.popupForeground,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batteryLabelFor(details.reading),
                style: TextStyle(
                  color: theme.popupForeground,
                  fontSize: ShellFontSizes.heading,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Text(
                batteryStatusLine(details),
                style: TextStyle(color: theme.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A `Table`, so the values line up whatever the labels' widths, and with no
/// flex column so it shrink-wraps — the forecast table's reasoning.
class _BatteryTable extends StatelessWidget {
  const _BatteryTable({required this.rows});

  final List<BatteryDetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final row in rows)
          if (row.isHeading)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: theme.popupForeground,
                      fontSize: ShellFontSizes.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox.shrink(),
              ],
            )
          else
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 16),
                  child: Text(
                    row.label,
                    style: TextStyle(color: theme.muted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(row.value!),
                ),
              ],
            ),
      ],
    );
  }
}

final Module batteryModule = Module.simple<BatteryConfig>(
  configKey: 'battery',
  fromMap: (map) {
    final config = BatteryConfig.fromMap(map);
    // The store, not the widget, owns the config: polling continues across
    // widget rebuilds, and every bar instance shares the one poller.
    BatteryStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const Battery(),
);
