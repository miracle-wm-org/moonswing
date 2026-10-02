import 'dart:async';
import 'dart:math' as math;

import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/dbus_clients.dart';
import 'package:moonswing/level_slider.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/osd/brightness_monitor.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/scroll_steps.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

/// Writes a raw level to a backlight device.
///
/// A seam so the store can be tested without a system bus.
typedef BacklightWriter = Future<void> Function(String device, int raw);

/// Sets [raw] on `/sys/class/backlight/<device>` through logind.
///
/// `brightness` in sysfs is root's to write; logind's `SetBrightness` is the
/// unprivileged route, and it allows exactly the caller whose session owns the
/// seat — which is the shell. `session/auto` is logind resolving the caller's
/// own session, so nothing here has to work out which one that is.
Future<void> logindSetBrightness(String device, int raw) async {
  final session = DBusRemoteObject(
    systemBus,
    name: 'org.freedesktop.login1',
    path: DBusObjectPath('/org/freedesktop/login1/session/auto'),
  );
  await session.callMethod(
    'org.freedesktop.login1.Session',
    'SetBrightness',
    [
      const DBusString('backlight'),
      DBusString(device),
      DBusUint32(raw),
    ],
    replySignature: DBusSignature(''),
  );
}

/// The raw value to write for [level] on a device whose range is [max].
///
/// Floored at 1% (and at least one step): on many panels a raw 0 switches the
/// backlight off outright, and a slider dragged to the bottom would otherwise
/// leave the user a black screen to find the slider on again.
int backlightRawFor(double level, int max) {
  final floor = math.max(1, (max / 100).ceil());
  return (level.clamp(0.0, 1.0) * max).round().clamp(floor, max);
}

/// The display backlight for the whole shell.
///
/// The lease shape every store has: the first lease finds the device and
/// starts the udev watch, the last one stops it, so an idle shell with the
/// module off holds nothing. Reading is [BrightnessMonitor]'s — sysfs, kept
/// live by udev, so a level changed by a brightness key or by anything else
/// shows here too. Writing goes through [BacklightWriter].
class BacklightStore extends ChangeNotifier {
  BacklightStore._({
    required String sysfsRoot,
    required BacklightWriter writer,
  })  : _sysfsRoot = sysfsRoot,
        _writer = writer;

  static final BacklightStore instance = BacklightStore._(
    sysfsRoot: '/sys/class/backlight',
    writer: logindSetBrightness,
  );

  @visibleForTesting
  factory BacklightStore.forTesting({
    required String sysfsRoot,
    required BacklightWriter writer,
  }) =>
      BacklightStore._(sysfsRoot: sysfsRoot, writer: writer);

  final String _sysfsRoot;
  final BacklightWriter _writer;

  // --- published state -----------------------------------------------------

  double? _level;

  /// The backlight level in 0..1, or null while there is no backlight — the
  /// normal state of a desktop machine, where the module draws nothing.
  double? get level => _level;

  String? _error;

  /// Why the last write did not land, or null after one that did. The level
  /// stays on screen either way; the next write is the retry.
  String? get error => _error;

  // --- lease ---------------------------------------------------------------

  int _leases = 0;
  BrightnessMonitor? _monitor;
  StreamSubscription<double>? _changes;

  /// Takes a lease. The first one reads the level synchronously and does not
  /// notify — it runs inside the acquirer's `initState`, which reads [level]
  /// on its first build anyway.
  void acquire() {
    _leases++;
    if (_monitor != null) return;
    final monitor = BrightnessMonitor(sysfsRoot: _sysfsRoot)..start();
    _monitor = monitor;
    _level = monitor.current;
    _changes = monitor.onChanged.listen((level) {
      if (level == _level) return;
      _level = level;
      notifyListeners();
    });
  }

  void release() {
    if (_leases > 0) _leases--;
    if (_leases > 0) return;
    _changes?.cancel();
    _changes = null;
    _monitor?.dispose();
    _monitor = null;
  }

  // --- writes --------------------------------------------------------------

  /// Sets the backlight to [level].
  ///
  /// Shown at once rather than on udev's echo, so a fast scroll steps from
  /// where the last notch put it instead of from a reading still in flight; the
  /// echo lands within a rounding of it.
  Future<void> setLevel(double level) async {
    final monitor = _monitor;
    final device = monitor?.deviceName;
    if (monitor == null || device == null) return;
    final max = monitor.maxBrightness;
    final raw = backlightRawFor(level, max);
    final shown = raw / max;
    if (shown != _level) {
      _level = shown;
      notifyListeners();
    }
    try {
      await _writer(device, raw);
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Could not set the brightness: $e');
      _error = 'Could not set the brightness through logind.';
      notifyListeners();
    }
  }

  /// Scrolling: [steps] notches up (positive) or down, on the shared grid.
  void step(int steps) {
    final current = _level;
    if (current == null) return;
    final next = scrolledLevel(current, steps);
    if (next == current) return;
    setLevel(next);
  }

  @override
  void dispose() {
    _changes?.cancel();
    _monitor?.dispose();
    super.dispose();
  }
}

class BrightnessControl extends StatefulWidget {
  const BrightnessControl({super.key});

  @override
  BrightnessControlState createState() => BrightnessControlState();
}

class BrightnessControlState extends State<BrightnessControl>
    with PopupHost<BrightnessControl> {
  final BacklightStore _store = BacklightStore.instance;

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

    final anchor = BarScope.of(context);
    final isVertical = anchor == 'top' || anchor == 'bottom';

    openBarPopup(
      context,
      // Pinned along the slider, for the reason `sound_control.dart` gives: a
      // slider has no intrinsic length, and a popup whose label changes width
      // under a drag would walk away from the bar.
      preferredConstraints: isVertical
          ? const BoxConstraints(minWidth: 80, maxWidth: 80, maxHeight: 320)
          : const BoxConstraints(minWidth: 240, maxWidth: 240, maxHeight: 200),
      child: ThemeProvider(
        child: _BrightnessPopupContent(store: _store, vertical: isVertical),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final level = _store.level;
        if (level == null) return const SizedBox.shrink();
        final theme = ThemeScope.of(context);
        return ScrollSteps(
          onSteps: _store.step,
          child: BarButton(
            active: isPopupOpen,
            onTapDown: (_) => _togglePopup(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(FontAwesomeIcons.sun, size: 12, color: theme.foreground),
                const SizedBox(width: 4),
                Text(
                  '${(level * 100).round()}%',
                  style: TextStyle(fontSize: 16, color: theme.foreground),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BrightnessPopupContent extends StatefulWidget {
  const _BrightnessPopupContent({required this.store, required this.vertical});

  /// Listened to rather than read once: the popup is its own window, built
  /// once, and the level moves under it whenever a brightness key is pressed.
  final BacklightStore store;
  final bool vertical;

  @override
  State<_BrightnessPopupContent> createState() =>
      _BrightnessPopupContentState();
}

class _BrightnessPopupContentState extends State<_BrightnessPopupContent> {
  /// A local copy, so a drag paints at the pointer rather than at whatever the
  /// backlight last reported. The slider writes only on release, so the two
  /// cannot fight mid-gesture.
  late double _level;

  @override
  void initState() {
    super.initState();
    _level = widget.store.level ?? 0.0;
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    setState(() => _level = widget.store.level ?? _level);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final error = widget.store.error;

    final icon = SizedBox.square(
      dimension: ShellSizes.minTapTarget,
      child: Center(
        child: FaIcon(
          FontAwesomeIcons.sun,
          size: ShellFontSizes.label,
          color: theme.popupForeground,
        ),
      ),
    );
    final label = Text('${(_level * 100).round()}%');
    final slider = LevelSlider(
      value: _level,
      enabled: true,
      axis: widget.vertical ? Axis.vertical : Axis.horizontal,
      onChanged: (v) => setState(() => _level = v),
      onChangeEnd: widget.store.setLevel,
    );

    final Widget controls = widget.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(height: 10),
              SizedBox(height: 120, child: slider),
              const SizedBox(height: 10),
              icon,
            ],
          )
        : Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(child: slider),
              const SizedBox(width: 8),
              label,
            ],
          );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              controls,
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: const TextStyle(
                    color: kErrorColor,
                    fontSize: ShellFontSizes.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final Module brightnessModule = Module.plain(
  configKey: 'brightness',
  builder: (_) => const BrightnessControl(),
);
