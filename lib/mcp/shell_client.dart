// The session-bus half of `moonswing-mcp`: the shell's own interface, and the
// two freedesktop ones it reaches any desktop through.
//
// `org.moonswing.Shell1` is the shell's (`lib/control/`). Posting a notification
// goes to `org.freedesktop.Notifications`, which the shell serves but any other
// daemon serves too, and media is MPRIS, which every player speaks — so those
// two tools work whether or not the shell is the one listening.
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

import 'package:moonswing/control/control_api.dart';
import 'package:moonswing/mcp/mcp_protocol.dart';

/// How long any one bus call may take. A screenshot is the slow one, and the
/// shell gives its grab five seconds of its own.
const Duration kShellCallTimeout = Duration(seconds: 15);

class ShellBusClient {
  ShellBusClient({DBusClient Function()? connect})
      : _connect = connect ?? DBusClient.session;

  final DBusClient Function() _connect;
  DBusClient? _client;

  DBusClient get _bus => _client ??= _connect();

  Future<void> close() async {
    final client = _client;
    _client = null;
    await client?.close();
  }

  /// Calls [method] on the shell and returns its values, turning the shell
  /// not running and the shell refusing into sentences.
  Future<List<DBusValue>> callShell(
    String method, [
    List<DBusValue> args = const [],
    String? replySignature,
  ]) async {
    try {
      final reply = await _bus
          .callMethod(
            destination: kShellControlBusName,
            path: DBusObjectPath(kShellControlObjectPath),
            interface: kShellControlInterface,
            name: method,
            values: args,
            replySignature:
                replySignature == null ? null : DBusSignature(replySignature),
          )
          .timeout(kShellCallTimeout);
      return reply.values;
    } on DBusServiceUnknownException {
      throw const McpToolException(
          'Moonswing is not running, or its control interface is switched '
          'off ([control] enabled = false in ~/.config/moonswing/config.toml).');
    } on DBusMethodResponseException catch (e) {
      throw McpToolException(_describe(e));
    } on TimeoutException {
      throw McpToolException('The shell did not answer $method in time.');
    }
  }

  static String _describe(DBusMethodResponseException e) {
    final values = e.response.values;
    final message =
        values.isNotEmpty && values.first is DBusString
            ? (values.first as DBusString).value
            : e.errorName;
    if (e.errorName == 'org.freedesktop.DBus.Error.UnknownMethod') {
      return 'This version of the shell has no such method — update '
          'Moonswing. ($message)';
    }
    return message;
  }

  /// Posts a notification through whichever daemon owns the name.
  Future<int> notify({
    required String summary,
    String body = '',
    String appName = 'AI agent',
    int timeoutMs = -1,
    String urgency = 'normal',
  }) async {
    final urgencyByte = switch (urgency) {
      'low' => 0,
      'critical' => 2,
      _ => 1,
    };
    try {
      final reply = await _bus
          .callMethod(
            destination: 'org.freedesktop.Notifications',
            path: DBusObjectPath('/org/freedesktop/Notifications'),
            interface: 'org.freedesktop.Notifications',
            name: 'Notify',
            values: [
              DBusString(appName),
              const DBusUint32(0),
              const DBusString(''),
              DBusString(summary),
              DBusString(body),
              DBusArray.string(const []),
              DBusDict.stringVariant({'urgency': DBusByte(urgencyByte)}),
              DBusInt32(timeoutMs),
            ],
            replySignature: DBusSignature('u'),
          )
          .timeout(kShellCallTimeout);
      return (reply.values.first as DBusUint32).value;
    } on DBusServiceUnknownException {
      throw const McpToolException('No notification daemon is running.');
    } on DBusMethodResponseException catch (e) {
      throw McpToolException(_describe(e));
    }
  }

  // --- MPRIS ---------------------------------------------------------------

  static const String _mprisPrefix = 'org.mpris.MediaPlayer2.';
  static const String _playerInterface = 'org.mpris.MediaPlayer2.Player';

  /// Every MPRIS player on the bus, by its short name (`spotify`,
  /// `firefox.instance_1_23`).
  Future<List<String>> mediaPlayers() async {
    final names = await _bus.listNames().timeout(kShellCallTimeout);
    return [
      for (final name in names)
        if (name.startsWith(_mprisPrefix)) name.substring(_mprisPrefix.length),
    ]..sort();
  }

  Future<String> _resolvePlayer(String? player) async {
    final players = await mediaPlayers();
    if (players.isEmpty) {
      throw const McpToolException('No media player is running.');
    }
    if (player == null || player.isEmpty) {
      // A playing one if there is one: "pause the music" means that player.
      for (final candidate in players) {
        final status = await _playerProperty(candidate, 'PlaybackStatus');
        if (status is DBusString && status.value == 'Playing') return candidate;
      }
      return players.first;
    }
    for (final candidate in players) {
      if (candidate == player) return candidate;
    }
    for (final candidate in players) {
      if (candidate.toLowerCase().startsWith(player.toLowerCase())) {
        return candidate;
      }
    }
    throw McpToolException(
        'There is no player "$player"; there are ${players.join(', ')}.');
  }

  Future<DBusValue?> _playerProperty(String player, String name) async {
    try {
      final reply = await _bus
          .callMethod(
            destination: '$_mprisPrefix$player',
            path: DBusObjectPath('/org/mpris/MediaPlayer2'),
            interface: 'org.freedesktop.DBus.Properties',
            name: 'Get',
            values: [const DBusString(_playerInterface), DBusString(name)],
            replySignature: DBusSignature('v'),
          )
          .timeout(const Duration(seconds: 3));
      return (reply.values.first as DBusVariant).value;
    } catch (_) {
      return null;
    }
  }

  /// What each player is doing.
  Future<List<Map<String, Object?>>> mediaStatus() async {
    final rows = <Map<String, Object?>>[];
    for (final player in await mediaPlayers()) {
      final status = await _playerProperty(player, 'PlaybackStatus');
      final metadata = await _playerProperty(player, 'Metadata');
      String? text(String key) {
        if (metadata is! DBusDict) return null;
        final value = metadata.children[DBusString(key)];
        final inner = value is DBusVariant ? value.value : value;
        if (inner is DBusString) return inner.value;
        if (inner is DBusArray && inner.children.isNotEmpty) {
          return inner.children
              .whereType<DBusString>()
              .map((s) => s.value)
              .join(', ');
        }
        return null;
      }

      rows.add({
        'player': player,
        'status': status is DBusString ? status.value : null,
        'title': text('xesam:title'),
        'artist': text('xesam:artist'),
        'album': text('xesam:album'),
      });
    }
    return rows;
  }

  /// Sends one MPRIS verb, returning which player it went to.
  Future<String> mediaControl(String action, {String? player}) async {
    final target = await _resolvePlayer(player);
    final method = switch (action) {
      'play' => 'Play',
      'pause' => 'Pause',
      'play_pause' => 'PlayPause',
      'stop' => 'Stop',
      'next' => 'Next',
      'previous' => 'Previous',
      _ => throw McpToolException('Unknown media action "$action".'),
    };
    try {
      await _bus
          .callMethod(
            destination: '$_mprisPrefix$target',
            path: DBusObjectPath('/org/mpris/MediaPlayer2'),
            interface: _playerInterface,
            name: method,
            replySignature: DBusSignature(''),
          )
          .timeout(kShellCallTimeout);
    } on DBusMethodResponseException catch (e) {
      throw McpToolException('$target refused $method: ${_describe(e)}');
    }
    return target;
  }
}
