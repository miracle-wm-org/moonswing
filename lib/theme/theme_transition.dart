import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/theme_store.dart';
import 'package:moonswing/theme/tokens.dart';

/// The theme on screen, which follows a source theme and blends into it when
/// the user *switches* themes rather than snapping.
///
/// A switch is told apart from an edit by [identity] — the active theme's
/// name. Picking Dracula over Glassy plays [duration] of [ThemeConfig.blend];
/// a colour-picker drag on the theme already active reaches [value] on the
/// notification it arrives in, because a picker that trailed the pointer by a
/// blend would be a broken picker. An edit landing mid-blend retargets it, and
/// a second switch starts a fresh one from whatever is on screen at the time,
/// so nothing jumps back to the palette being left.
///
/// What blends is the palette and `font_size` (through the `TextScaler`
/// `ThemeProvider` publishes). A font *family* cannot: there is no halfway
/// between two typefaces, and drawing every string in the shell twice to
/// cross-fade them would cost every surface a second layer for the length of
/// the switch. It changes on the first frame, with the rest of what
/// [ThemeConfig.blend] takes from the new theme at once.
///
/// One for the process ([instance], every window but the bars) plus one over
/// the panels' `PanelReachSequencer`, which lags the store by the frames a
/// surface takes to grow. Nothing animates at rest: the [Ticker] exists only
/// while a blend is playing, and progress is read off its elapsed time — the
/// frame clock — rather than counted per tick.
class ThemeTransition extends ChangeNotifier
    implements ValueListenable<ThemeConfig> {
  ThemeTransition({
    required Listenable source,
    required ThemeConfig Function() read,
    required Object? Function() identity,
    this.duration = ShellDurations.themeSwitch,
    this.curve = Curves.easeInOut,
  })  : _source = source,
        _read = read,
        _identity = identity,
        _value = read(),
        _id = identity() {
    source.addListener(_onSource);
  }

  /// Follows [store], a switch being a change of its active theme's name.
  factory ThemeTransition.ofStore(ThemeStore store) => ThemeTransition(
        source: store,
        read: () => store.theme,
        identity: () => store.activeName,
      );

  /// What every `ThemeProvider` not handed a theme of its own follows.
  static final ThemeTransition instance =
      ThemeTransition.ofStore(ThemeStore.instance);

  final Duration duration;
  final Curve curve;

  final Listenable _source;
  final ThemeConfig Function() _read;
  final Object? Function() _identity;

  ThemeConfig _value;
  Object? _id;

  /// The blend under way: from what was on screen when it started, to the
  /// source's theme. Meaningful only while [_ticker] exists.
  ThemeConfig? _from;
  late ThemeConfig _to;
  double _progress = 0;
  Ticker? _ticker;

  @override
  ThemeConfig get value => _value;

  /// Whether a blend is playing.
  bool get isBlending => _ticker != null;

  void _onSource() {
    final next = _read();
    final id = _identity();
    final switched = id != _id;
    _id = id;

    if (!switched || duration <= Duration.zero) {
      if (isBlending) {
        // An edit mid-switch: same progress, new destination.
        _to = next;
        _show(ThemeConfig.blend(_from!, _to, curve.transform(_progress)));
      } else {
        _show(next);
      }
      return;
    }
    if (next == _value) {
      _stop();
      _show(next);
      return;
    }
    _from = _value;
    _to = next;
    _progress = 0;
    final ticker = _ticker ??= Ticker(_tick, debugLabel: 'ThemeTransition');
    // From zero again when a switch interrupts one under way.
    ticker
      ..stop()
      ..start();
    // Everything that does not blend lands now, with the store's other readers.
    _show(ThemeConfig.blend(_from!, _to, 0));
  }

  void _tick(Duration elapsed) {
    _progress = elapsed.inMicroseconds / duration.inMicroseconds;
    if (_progress >= 1) {
      _stop();
      _show(_to);
      return;
    }
    _show(ThemeConfig.blend(_from!, _to, curve.transform(_progress)));
  }

  void _stop() {
    _ticker?.dispose();
    _ticker = null;
    _from = null;
  }

  void _show(ThemeConfig theme) {
    if (theme == _value) return;
    _value = theme;
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_onSource);
    _stop();
    super.dispose();
  }
}
