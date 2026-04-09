import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/scopes.dart';

class MediaPlayerConfig {
  final double maxTextWidth;

  const MediaPlayerConfig({this.maxTextWidth = 200.0});

  factory MediaPlayerConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MediaPlayerConfig();
    return MediaPlayerConfig(
      maxTextWidth: (map['max_text_width'] as num?)?.toDouble() ?? 200.0,
    );
  }
}

const String _mprisPrefix = 'org.mpris.MediaPlayer2.';
const String _playerInterface = 'org.mpris.MediaPlayer2.Player';
const String _mprisPath = '/org/mpris/MediaPlayer2';
const int _marqueeThreshold = 32;
const double _marqueeGap = 40.0;
const double _marqueePixelsPerMs = 0.033;

class _PlayerState {
  _PlayerState({required this.busName});

  final String busName;
  String playbackStatus = 'Stopped';
  String title = '';
  String artist = '';
  bool canPlay = false;
  bool canPause = false;
  bool canGoNext = false;
  bool canGoPrevious = false;
  bool canControl = false;
}

class MediaPlayer extends StatefulWidget {
  const MediaPlayer({super.key, required this.config});

  final MediaPlayerConfig config;

  @override
  MediaPlayerState createState() => MediaPlayerState();
}

class MediaPlayerState extends State<MediaPlayer>
    with SingleTickerProviderStateMixin {
  DBusClient? _dbus;
  StreamSubscription<DBusNameOwnerChangedEvent>? _nameOwnerSub;
  final Map<String, _PlayerState> _players = {};
  final Map<String, StreamSubscription<DBusPropertiesChangedSignal>> _propSubs =
      {};
  _PlayerState? _activePlayer;
  String _displayText = '';
  double _textWidth = 0;
  String _fontFamily = 'Ubuntu Sans';

  late final AnimationController _scrollController;

  // Used only for TextPainter width measurement — color has no effect on layout.
  TextStyle get _measureStyle =>
      TextStyle(fontFamily: _fontFamily, fontSize: 12);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fontFamily = ThemeScope.of(context).fontFamily;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = AnimationController(vsync: this);
    _initDbus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameOwnerSub?.cancel();
    for (final sub in _propSubs.values) {
      sub.cancel();
    }
    _dbus?.close();
    super.dispose();
  }

  Future<void> _initDbus() async {
    try {
      _dbus = DBusClient.session();
      _nameOwnerSub = _dbus!.nameOwnerChanged.listen(_onNameOwnerChanged);
      await _scanForPlayers();
    } catch (_) {
      // D-Bus unavailable — widget stays hidden
    }
  }

  Future<void> _scanForPlayers() async {
    if (_dbus == null) return;
    try {
      final names = await _dbus!.listNames();
      for (final name in names) {
        if (name.startsWith(_mprisPrefix)) {
          await _addPlayer(name);
        }
      }
    } catch (_) {}
  }

  Future<void> _addPlayer(String busName) async {
    if (_players.containsKey(busName) || _dbus == null) return;

    final player = _PlayerState(busName: busName);
    _players[busName] = player;

    final obj = DBusRemoteObject(
      _dbus!,
      name: busName,
      path: DBusObjectPath(_mprisPath),
    );

    try {
      final props = await obj.getAllProperties(_playerInterface);
      _applyProperties(player, props);
    } catch (_) {
      // Player may have vanished before we could query it
      _players.remove(busName);
      return;
    }

    _propSubs[busName] = obj.propertiesChanged.listen((signal) {
      if (signal.propertiesInterface == _playerInterface) {
        _applyProperties(player, signal.changedProperties);
        _selectActivePlayer();
        _updateDisplayText();
        if (mounted) setState(() {});
      }
    });

    _selectActivePlayer();
    _updateDisplayText();
    if (mounted) setState(() {});
  }

  void _removePlayer(String busName) {
    _propSubs[busName]?.cancel();
    _propSubs.remove(busName);
    _players.remove(busName);
    _selectActivePlayer();
    _updateDisplayText();
    if (mounted) setState(() {});
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (!event.name.startsWith(_mprisPrefix)) return;

    if (event.newOwner != null && event.newOwner!.isNotEmpty) {
      _addPlayer(event.name);
    } else {
      _removePlayer(event.name);
    }
  }

  void _applyProperties(_PlayerState player, Map<String, DBusValue> props) {
    if (props.containsKey('PlaybackStatus')) {
      player.playbackStatus = (props['PlaybackStatus'] as DBusString).value;
    }
    if (props.containsKey('Metadata')) {
      _applyMetadata(player, props['Metadata']!);
    }
    if (props.containsKey('CanPlay')) {
      player.canPlay = (props['CanPlay'] as DBusBoolean).value;
    }
    if (props.containsKey('CanPause')) {
      player.canPause = (props['CanPause'] as DBusBoolean).value;
    }
    if (props.containsKey('CanGoNext')) {
      player.canGoNext = (props['CanGoNext'] as DBusBoolean).value;
    }
    if (props.containsKey('CanGoPrevious')) {
      player.canGoPrevious = (props['CanGoPrevious'] as DBusBoolean).value;
    }
    if (props.containsKey('CanControl')) {
      player.canControl = (props['CanControl'] as DBusBoolean).value;
    }
  }

  void _applyMetadata(_PlayerState player, DBusValue metadataValue) {
    // Metadata is a{sv} — Dict<String, Variant>
    final dict = metadataValue as DBusDict;
    final metadata = <String, DBusValue>{};
    for (final entry in dict.children.entries) {
      final key = (entry.key as DBusString).value;
      final val = (entry.value as DBusVariant).value;
      metadata[key] = val;
    }

    if (metadata.containsKey('xesam:title')) {
      player.title = (metadata['xesam:title'] as DBusString).value;
    } else {
      player.title = '';
    }

    if (metadata.containsKey('xesam:artist')) {
      final artists = metadata['xesam:artist'] as DBusArray;
      player.artist =
          artists.children.map((v) => (v as DBusString).value).join(', ');
    } else {
      player.artist = '';
    }
  }

  void _selectActivePlayer() {
    // Prefer currently active player if still playing
    if (_activePlayer != null &&
        _players.containsKey(_activePlayer!.busName) &&
        _activePlayer!.playbackStatus == 'Playing') {
      return;
    }

    // Find any playing player
    for (final player in _players.values) {
      if (player.playbackStatus == 'Playing') {
        _activePlayer = player;
        return;
      }
    }

    // Fall back to paused
    for (final player in _players.values) {
      if (player.playbackStatus == 'Paused') {
        _activePlayer = player;
        return;
      }
    }

    _activePlayer = null;
  }

  String _formatDisplayText() {
    if (_activePlayer == null) return '';
    final player = _activePlayer!;
    if (player.title.isEmpty && player.artist.isEmpty) {
      // Fall back to player identity from bus name
      return player.busName.substring(_mprisPrefix.length);
    }
    if (player.artist.isEmpty) return player.title;
    return '${player.artist} — ${player.title}';
  }

  void _updateDisplayText() {
    final text = _formatDisplayText();
    _displayText = text;

    if (text.length > _marqueeThreshold) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _measureStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      _textWidth = painter.width;
      painter.dispose();

      final totalScroll = _textWidth + _marqueeGap;
      final durationMs = (totalScroll / _marqueePixelsPerMs).toInt();
      _scrollController.duration = Duration(milliseconds: durationMs);
      _scrollController.repeat();
    } else {
      _scrollController.stop();
      _scrollController.reset();
    }
  }

  Future<void> _callMethod(String method) async {
    if (_activePlayer == null || _dbus == null) return;
    try {
      final obj = DBusRemoteObject(
        _dbus!,
        name: _activePlayer!.busName,
        path: DBusObjectPath(_mprisPath),
      );
      await obj.callMethod(_playerInterface, method, []);
    } catch (_) {}
  }

  void _playPause() => _callMethod('PlayPause');
  void _next() => _callMethod('Next');
  void _previous() => _callMethod('Previous');
  void _stop() => _callMethod('Stop');

  Widget _buildTrackText(BuildContext context) {
    if (_displayText.isEmpty) return const SizedBox.shrink();

    final style =
        _measureStyle.copyWith(color: ThemeScope.of(context).foreground);

    if (_displayText.length <= _marqueeThreshold) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.config.maxTextWidth),
        child: Text(
          _displayText,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return SizedBox(
      width: widget.config.maxTextWidth,
      height: 16,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            final totalWidth = _textWidth + _marqueeGap;
            final offset = _scrollController.value * totalWidth;
            return Transform.translate(
              offset: Offset(-offset, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_displayText,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible),
              SizedBox(width: _marqueeGap),
              Text(_displayText,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activePlayer == null) return const SizedBox.shrink();

    final player = _activePlayer!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (player.canGoPrevious && player.canControl)
          _PanelIconButton(
              icon: FontAwesomeIcons.backwardStep, onPressed: _previous),
        if (player.canControl && (player.canPlay || player.canPause))
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _PanelIconButton(
              icon: player.playbackStatus == 'Playing'
                  ? FontAwesomeIcons.pause
                  : FontAwesomeIcons.play,
              onPressed: _playPause,
            ),
          ),
        if (player.canControl)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child:
                _PanelIconButton(icon: FontAwesomeIcons.stop, onPressed: _stop),
          ),
        if (player.canGoNext && player.canControl)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _PanelIconButton(
                icon: FontAwesomeIcons.forwardStep, onPressed: _next),
          ),
        const SizedBox(width: 6),
        _buildTrackText(context),
      ],
    );
  }
}

class _PanelIconButton extends StatefulWidget {
  const _PanelIconButton({
    required this.icon,
    required this.onPressed,
  });

  final FaIconData icon;
  final VoidCallback onPressed;

  @override
  State<_PanelIconButton> createState() => _PanelIconButtonState();
}

class _PanelIconButtonState extends State<_PanelIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    Color color;
    if (_pressed) {
      color = theme.surfacePressed;
    } else if (_hovered) {
      color = theme.surfaceHover;
    } else {
      color = const Color(0x00000000);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SizedBox(
            width: 14,
            height: 14,
            child: Center(
              child: FaIcon(
                widget.icon,
                size: 12,
                color: theme.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MediaPlayerModule extends Module {
  MediaPlayerConfig _config = const MediaPlayerConfig();

  @override
  String get configKey => 'media_player';

  @override
  void loadConfig(Map<String, dynamic>? map) {
    _config = MediaPlayerConfig.fromMap(map);
  }

  @override
  WidgetBuilder get builder => (context) => MediaPlayer(config: _config);
}
