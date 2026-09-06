import 'dart:async';
// `widgets.dart` re-exports foundation with a `show` list that carries
// ValueNotifier but not ValueListenable, which is what the popup takes.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/pulse_client.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/theme/theme_provider.dart';

/// A sink's level as the shell last saw it.
///
/// A record, so the notifier below gets structural equality for free and does
/// not wake its listeners for a PulseAudio event that moved nothing — and
/// PulseAudio emits plenty of those (a stream connecting, a port switch).
typedef _SinkLevel = ({double volume, bool muted});

FaIconData _volumeIconFor(_SinkLevel level) {
  if (level.muted) return FontAwesomeIcons.volumeXmark;
  if (level.volume <= 0.0) return FontAwesomeIcons.volumeOff;
  if (level.volume <= 0.5) return FontAwesomeIcons.volumeLow;
  return FontAwesomeIcons.volumeHigh;
}

class SoundControl extends StatefulWidget {
  const SoundControl({super.key});

  @override
  SoundControlState createState() => SoundControlState();
}

class SoundControlState extends State<SoundControl>
    with PopupHost<SoundControl> {
  /// The default sink's level.
  ///
  /// A notifier rather than a pair of `setState` fields because the popup is its
  /// own layer-shell window, built once into a `WindowEntry` builder — the parent
  /// never rebuilds it, so a popup handed a *value* freezes at whatever was
  /// current when it opened. It is also what carries a device switch into an
  /// already-open popup.
  final _level = ValueNotifier<_SinkLevel>((volume: 0.0, muted: false));

  /// The sink every read and write goes to. Re-resolved whenever PulseAudio
  /// reports the default moving — see the `onServerChanged` listener.
  String _defaultSinkName = '';
  bool _available = false;
  PulseClient? _client;
  StreamSubscription<PaSink>? _sinkChangedSub;
  StreamSubscription<PaServerInfo>? _serverChangedSub;
  StreamSubscription<void>? _reconnectedSub;

  @override
  void initState() {
    super.initState();
    _initPulseAudio();
  }

  @override
  void dispose() {
    _sinkChangedSub?.cancel();
    _serverChangedSub?.cancel();
    _reconnectedSub?.cancel();
    closePopup();
    _level.dispose();
    super.dispose();
  }

  Future<void> _initPulseAudio() async {
    try {
      final client = PulseClient();
      await client.initialize();
      _client = client;

      // Subscribe before the first query, never after. These subscriptions are
      // the only thing that keeps the reading live, and a query that throws or
      // never answers would otherwise cost them for the rest of the session.
      // `_defaultSinkName` is empty until the queries land, which just drops
      // the events until then.
      _sinkChangedSub = client.onSinkChanged.listen((sink) {
        if (sink.name != _defaultSinkName) return;
        _level.value = (volume: sink.volume, muted: sink.mute);
      });

      // A default sink moving is reported on PulseAudio's *server* facility and
      // nowhere else: the sink being adopted emits no event of its own. Without
      // this the module goes on filtering events against the name it resolved at
      // start-up, reporting the level of a device the user has stopped listening
      // to — and its slider keeps writing to that device too.
      _serverChangedSub = client.onServerChanged.listen((info) {
        if (info.defaultSinkName == _defaultSinkName) return;
        _adoptDefaultSink(info.defaultSinkName);
      });

      // The server went away and came back. The re-read is unconditional, unlike
      // the `onServerChanged` one above: a restart normally brings the same sink
      // name back, so a name compare would answer "nothing moved" and leave the
      // module showing the level it read from the server that died.
      _reconnectedSub = client.onReconnected.listen((_) async {
        try {
          final info = await client.getServerInfo();
          if (!mounted) return;
          await _adoptDefaultSink(info.defaultSinkName);
        } catch (e) {
          debugPrint('Could not re-read the default sink after a reconnect: $e');
        }
      });

      final serverInfo = await client.getServerInfo();
      await _adoptDefaultSink(serverInfo.defaultSinkName);
    } catch (e) {
      debugPrint('Sound module unavailable: $e');
    }
  }

  /// Points the module at [name] and reads the level it is currently at.
  ///
  /// The name is committed before the query, so an event for the newly adopted
  /// device landing while the query is in flight is kept rather than filtered out
  /// against the name being left.
  ///
  /// `_available` is only ever set, never cleared: a sink the shell cannot find is
  /// far more likely to be a device mid-switch than a machine that has lost its
  /// audio, and a module that popped out of the bar on every switch would be
  /// worse than one showing a stale reading for a moment.
  Future<void> _adoptDefaultSink(String name) async {
    _defaultSinkName = name;
    final client = _client;
    if (client == null) return;
    try {
      for (final sink in await client.getSinkList()) {
        if (sink.name != name) continue;
        // A second switch may have superseded this one while the list was in
        // flight; its own call owns the level from then on.
        if (!mounted || _defaultSinkName != name) return;
        _level.value = (volume: sink.volume, muted: sink.mute);
        if (!_available) setState(() => _available = true);
        return;
      }
    } catch (e) {
      debugPrint('Could not read the default sink: $e');
    }
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }

    final anchor = BarScope.of(context);
    final client = _client;
    final isVertical = anchor == 'top' || anchor == 'bottom';

    openBarPopup(
      context,
      // Height hugs the content; width stays pinned, both deliberately. A slider
      // has no intrinsic length — _VolumeSlider paints through a CustomPaint
      // sized `double.infinity` along its axis — and this is the one popup that
      // rebuilds while open, swapping its label between `Muted`, `5%` and `100%`
      // on every drag. Flutter's Linux popup does not set the positioner's
      // reactive flag, so a content-width popup would walk away from the bar
      // under the pointer.
      preferredConstraints: isVertical
          ? const BoxConstraints(minWidth: 80, maxWidth: 80, maxHeight: 320)
          : const BoxConstraints(minWidth: 240, maxWidth: 240, maxHeight: 200),
      child: ThemeProvider(
        child: _SoundPopupContent(
          level: _level,
          vertical: isVertical,
          // `_defaultSinkName` is read at call time, never captured into these
          // closures: the default sink can move while the popup is open, and a
          // captured name would go on writing to the device the user left.
          onVolumeChanged: (v) => client?.setSinkVolume(_defaultSinkName, v),
          onMuteChanged: (m) => client?.setSinkMute(_defaultSinkName, m),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();

    final theme = ThemeScope.of(context);
    return ValueListenableBuilder<_SinkLevel>(
      valueListenable: _level,
      builder: (context, level, _) => BarButton(
        active: isPopupOpen,
        onTapDown: (_) => _togglePopup(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              _volumeIconFor(level),
              size: 12,
              color: theme.foreground,
            ),
            const SizedBox(width: 4),
            Text(
              '${(level.volume * 100).round()}%',
              style: TextStyle(fontSize: 16, color: theme.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundPopupContent extends StatefulWidget {
  const _SoundPopupContent({
    required this.level,
    required this.vertical,
    required this.onVolumeChanged,
    required this.onMuteChanged,
  });

  /// Listened to rather than read once — see [SoundControlState._level] for
  /// why a popup cannot be handed a plain value.
  final ValueListenable<_SinkLevel> level;
  final bool vertical;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<bool> onMuteChanged;

  @override
  _SoundPopupContentState createState() => _SoundPopupContentState();
}

class _SoundPopupContentState extends State<_SoundPopupContent> {
  /// A local copy, so a drag paints at the pointer rather than at whatever
  /// PulseAudio last reported. The slider writes only on release, so the two
  /// cannot fight mid-gesture.
  late _SinkLevel _level;

  @override
  void initState() {
    super.initState();
    _level = widget.level.value;
    widget.level.addListener(_onDeviceLevel);
  }

  @override
  void dispose() {
    widget.level.removeListener(_onDeviceLevel);
    super.dispose();
  }

  void _onDeviceLevel() {
    if (!mounted) return;
    setState(() => _level = widget.level.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final muted = _level.muted;
    final volume = _level.volume;

    // A bare `FaIcon` is a target the size of one glyph, and this one had no
    // `MouseRegion` either — the popup is tighter than a settings row, so it
    // takes the minimum box rather than `SettingsIconButton`'s.
    final muteButton = HoverRegion(
      onTap: () {
        final newMuted = !muted;
        setState(() => _level = (volume: volume, muted: newMuted));
        widget.onMuteChanged(newMuted);
      },
      builder: (context, hovered) => SizedBox.square(
        dimension: ShellSizes.minTapTarget,
        child: Center(
          child: FaIcon(
            _volumeIconFor(_level),
            size: ShellFontSizes.label,
            color: muted
                ? theme.muted
                : (hovered ? theme.accent : theme.popupForeground),
          ),
        ),
      ),
    );

    final volumeLabel = Text(muted ? 'Muted' : '${(volume * 100).round()}%');

    void onChanged(double v) =>
        setState(() => _level = (volume: v, muted: muted));

    final content = widget.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              volumeLabel,
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: _VolumeSlider(
                  value: muted ? 0.0 : volume,
                  enabled: !muted,
                  axis: Axis.vertical,
                  onChanged: onChanged,
                  onChangeEnd: widget.onVolumeChanged,
                ),
              ),
              const SizedBox(height: 10),
              muteButton,
            ],
          )
        : Row(
            children: [
              muteButton,
              const SizedBox(width: 8),
              Expanded(
                child: _VolumeSlider(
                  value: muted ? 0.0 : volume,
                  enabled: !muted,
                  onChanged: onChanged,
                  onChangeEnd: widget.onVolumeChanged,
                ),
              ),
              const SizedBox(width: 8),
              volumeLabel,
            ],
          );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(color: theme.popupForeground, fontSize: 13),
        child: PopupCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: content,
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Axis axis;

  double _valueFromPosition(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    if (axis == Axis.vertical) {
      return (1.0 - local.dy / box.size.height).clamp(0.0, 1.0);
    }
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final painter = _SliderPainter(
      value: value,
      enabled: enabled,
      axis: axis,
      trackColor: theme.sliderTrack,
      activeFillColor: theme.accent,
      inactiveFillColor: theme.sliderTrack,
      activeThumbColor: theme.popupForeground,
      inactiveThumbColor: theme.sliderTrack,
    );

    if (axis == Axis.vertical) {
      return GestureDetector(
        onVerticalDragUpdate: !enabled
            ? null
            : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
        onVerticalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
        onTapDown: !enabled
            ? null
            : (d) {
                final v = _valueFromPosition(context, d.globalPosition);
                onChanged(v);
                onChangeEnd(v);
              },
        child: CustomPaint(
          size: const Size(20, double.infinity),
          painter: painter,
        ),
      );
    }
    return GestureDetector(
      onHorizontalDragUpdate: !enabled
          ? null
          : (d) => onChanged(_valueFromPosition(context, d.globalPosition)),
      onHorizontalDragEnd: !enabled ? null : (d) => onChangeEnd(value),
      onTapDown: !enabled
          ? null
          : (d) {
              final v = _valueFromPosition(context, d.globalPosition);
              onChanged(v);
              onChangeEnd(v);
            },
      child: CustomPaint(
        size: const Size(double.infinity, 20),
        painter: painter,
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({
    required this.value,
    required this.enabled,
    required this.trackColor,
    required this.activeFillColor,
    required this.inactiveFillColor,
    required this.activeThumbColor,
    required this.inactiveThumbColor,
    this.axis = Axis.horizontal,
  });

  final double value;
  final bool enabled;
  final Axis axis;
  final Color trackColor;
  final Color activeFillColor;
  final Color inactiveFillColor;
  final Color activeThumbColor;
  final Color inactiveThumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (axis == Axis.vertical) {
      final trackX = size.width / 2;
      final thumbY = (1.0 - value) * size.height;

      // Track background
      canvas.drawLine(
        Offset(trackX, 0),
        Offset(trackX, size.height),
        Paint()
          ..color = trackColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

      // Track fill (bottom up)
      if (thumbY < size.height) {
        canvas.drawLine(
          Offset(trackX, size.height),
          Offset(trackX, thumbY),
          Paint()
            ..color = enabled ? activeFillColor : inactiveFillColor
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }

      // Thumb
      canvas.drawCircle(
        Offset(trackX, thumbY),
        6,
        Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
      );
      return;
    }

    final trackY = size.height / 2;
    final thumbX = value * size.width;

    // Track background
    canvas.drawLine(
      Offset(0, trackY),
      Offset(size.width, trackY),
      Paint()
        ..color = trackColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Track fill
    if (thumbX > 0) {
      canvas.drawLine(
        Offset(0, trackY),
        Offset(thumbX, trackY),
        Paint()
          ..color = enabled ? activeFillColor : inactiveFillColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Thumb
    canvas.drawCircle(
      Offset(thumbX, trackY),
      6,
      Paint()..color = enabled ? activeThumbColor : inactiveThumbColor,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.value != value ||
      old.enabled != enabled ||
      old.axis != axis ||
      old.trackColor != trackColor ||
      old.activeFillColor != activeFillColor ||
      old.activeThumbColor != activeThumbColor;
}

final Module soundControlModule = Module.plain(
  configKey: 'sound_control',
  builder: (_) => const SoundControl(),
);
