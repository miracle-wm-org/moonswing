// Moonswing on a compositor that is not Miracle WM — sway, Miriway.
//
// Everything miracle-only must either render nothing or say why, and nothing
// may wait on an answer that compositor will never send: sway logs a miracle
// message type it does not know and replies with nothing at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/capture/capture_menu.dart';
import 'package:moonswing/capture/selection_controller.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/input_trigger/input_trigger_service.dart';
import 'package:moonswing/keybinds/shell_keybind_store.dart';
import 'package:moonswing/keybinds/shell_keybinds.dart';
import 'package:moonswing/miracle_manager.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/modules/clock.dart';
import 'package:moonswing/modules/scratchpad.dart';
import 'package:moonswing/modules/workspaces.dart';
import 'package:moonswing/scopes.dart';

/// An i3-ipc server on a unix socket: answers `SUBSCRIBE` (and, when
/// [speaksMiracle], miracle's own `GET_KEYBINDS`), and like sway says nothing
/// at all to a message type it does not know.
class _FakeIpcServer {
  _FakeIpcServer._(this.path, this._server, {required this.speaksMiracle}) {
    _server.listen((socket) {
      sockets.add(socket);
      var buffer = <int>[];
      socket.listen((data) {
        buffer = [...buffer, ...data];
        while (buffer.length >= 14) {
          final view = ByteData.sublistView(Uint8List.fromList(buffer));
          final length = view.getUint32(6, Endian.host);
          final type = view.getUint32(10, Endian.host);
          if (buffer.length < 14 + length) break;
          buffer = buffer.sublist(14 + length);
          received.add(type);
          final reply = switch (type) {
            2 => '{"success":true}',
            202 when speaksMiracle => '{"keybinds":[]}',
            _ => null,
          };
          if (reply != null) _send(socket, type, reply);
        }
      });
    });
  }

  static Future<_FakeIpcServer> start(
    Directory dir, {
    required bool speaksMiracle,
  }) async {
    final path = '${dir.path}/ipc.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _FakeIpcServer._(path, server, speaksMiracle: speaksMiracle);
  }

  final String path;
  final ServerSocket _server;
  final bool speaksMiracle;
  final List<Socket> sockets = [];
  final List<int> received = [];

  static void _send(Socket socket, int type, String payload) {
    final body = utf8.encode(payload);
    final header = ByteData(14);
    final magic = utf8.encode('i3-ipc');
    for (var i = 0; i < 6; i++) {
      header.setUint8(i, magic[i]);
    }
    header
      ..setUint32(6, body.length, Endian.host)
      ..setUint32(10, type, Endian.host);
    socket.add([...header.buffer.asUint8List(), ...body]);
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

void main() {
  group('detectMiracleSession', () {
    test('MIRACLESOCK is miracle, whatever else is set', () {
      expect(
        detectMiracleSession({
          'MIRACLESOCK': '/run/user/1000/miracle.sock',
          'SWAYSOCK': '/run/user/1000/miracle.sock',
          'XDG_CURRENT_DESKTOP': 'something-else',
        }),
        MiracleSession.miracle,
      );
    });

    test('the desktop name is read in either order and any case', () {
      for (final desktop in ['mir:miracle-wm', 'miracle-wm:mir', 'Miracle-WM']) {
        expect(
          detectMiracleSession({'XDG_CURRENT_DESKTOP': desktop}),
          MiracleSession.miracle,
          reason: desktop,
        );
      }
    });

    test('sway and Miriway are other compositors', () {
      expect(
        detectMiracleSession({
          'XDG_CURRENT_DESKTOP': 'sway',
          'SWAYSOCK': '/run/user/1000/sway-ipc.sock',
        }),
        MiracleSession.other,
      );
      expect(
        detectMiracleSession({'XDG_CURRENT_DESKTOP': 'Miriway'}),
        MiracleSession.other,
      );
    });

    test('no socket and no desktop name is not miracle', () {
      expect(detectMiracleSession(const {}), MiracleSession.other);
      expect(
        detectMiracleSession({'XDG_CURRENT_DESKTOP': '', 'SWAYSOCK': ''}),
        MiracleSession.other,
      );
    });

    test('a bare i3-compatible socket has to be asked', () {
      expect(
        detectMiracleSession({'SWAYSOCK': '/run/user/1000/sway-ipc.sock'}),
        MiracleSession.undetermined,
      );
      expect(
        detectMiracleSession({'I3SOCK': '/run/user/1000/i3/ipc-socket'}),
        MiracleSession.undetermined,
      );
    });
  });

  group('MiracleManager', () {
    late Directory dir;
    _FakeIpcServer? server;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moonswing-ipc-');
    });

    tearDown(() async {
      await server?.close();
      server = null;
      await dir.delete(recursive: true);
    });

    test('on another compositor it is unsupported from the start, and never '
        'connects', () async {
      final manager = MiracleManager(
        environment: {
          'XDG_CURRENT_DESKTOP': 'sway',
          'SWAYSOCK': '${dir.path}/nothing-here.sock',
        },
      );
      expect(manager.unsupported, isTrue);
      expect(manager.lastError, kNotMiracleMessage);

      await manager.connect();
      expect(manager.connection, isNull);
      expect(manager.connecting, isFalse);
      expect(manager.unsupported, isTrue);
    });

    test('a socket that ignores miracle\'s own request is not miracle\'s',
        () async {
      server = await _FakeIpcServer.start(dir, speaksMiracle: false);
      final manager = MiracleManager(
        environment: {'SWAYSOCK': server!.path},
        probeTimeout: const Duration(milliseconds: 200),
      );
      expect(manager.unsupported, isFalse);

      var notified = 0;
      manager.addListener(() => notified++);
      await manager.connect();

      expect(manager.unsupported, isTrue);
      expect(manager.connection, isNull);
      expect(manager.lastError, kNotMiracleMessage);
      expect(notified, greaterThan(0));
      // Asked once, and never subscribed: sway's events are not miracle's.
      expect(server!.received, [202]);

      // And settled for good — a retry asks nothing.
      await manager.connect();
      expect(server!.received, [202]);
    });

    test('a socket that answers it is connected to and subscribed', () async {
      server = await _FakeIpcServer.start(dir, speaksMiracle: true);
      final manager = MiracleManager(environment: {'SWAYSOCK': server!.path});

      await manager.connect();

      expect(manager.unsupported, isFalse);
      expect(manager.connection, isNotNull);
      expect(server!.received, [202, 2]);
      await manager.connection!.disconnect();
    });

    test('MIRACLESOCK is trusted without asking', () async {
      server = await _FakeIpcServer.start(dir, speaksMiracle: true);
      final manager = MiracleManager(environment: {'MIRACLESOCK': server!.path});

      await manager.connect();

      expect(manager.connection, isNotNull);
      expect(server!.received, [2]);
      await manager.connection!.disconnect();
    });

    test('a request miracle never answers times out instead of hanging',
        () async {
      server = await _FakeIpcServer.start(dir, speaksMiracle: false);
      final manager = MiracleManager(
        environment: {'MIRACLESOCK': server!.path},
        requestTimeout: const Duration(milliseconds: 200),
      );
      await manager.connect();
      final connection = manager.connection!;

      await expectLater(
        connection.getKeybinds(),
        throwsA(isA<TimeoutException>()),
      );
      await connection.disconnect();
    });
  });

  group('global shortcuts', () {
    test('the Miracle-only ones are not registered on another compositor', () {
      final names = {
        for (final s in inputShortcutsFor(
          const ShortcutsConfig(),
          miracle: false,
        ))
          s.name,
      };
      expect(names.intersection(kMiracleOnlyShortcuts), isEmpty);
      expect(names, contains('moonswing.open-launcher'));
    });

    test('and are on Miracle', () {
      final names = {
        for (final s in inputShortcutsFor(const ShortcutsConfig())) s.name,
      };
      expect(names, containsAll(kMiracleOnlyShortcuts));
    });

    test('the sheet leaves their rows out on another compositor', () {
      final store = ShellKeybindStore.forTesting(
        miracle: MiracleManager(environment: {'XDG_CURRENT_DESKTOP': 'sway'}),
      );
      expect(store.miracleUnsupported, isTrue);
      expect(store.shown.where((s) => s.needsMiracle), isEmpty);
      expect(store.shown, contains(ShellShortcut.openLauncher));

      final onMiracle = ShellKeybindStore.forTesting(
        miracle: MiracleManager(
          environment: {'XDG_CURRENT_DESKTOP': 'mir:miracle-wm'},
        ),
      );
      expect(onMiracle.shown, ShellShortcut.values);
    });

    test('every row the sheet hides is a registration that is dropped', () {
      // Two lists naming the same four things; this is what keeps them so.
      final hidden = ShellShortcut.values.where((s) => s.needsMiracle);
      final dropped = inputShortcutsFor(const ShortcutsConfig())
          .where((s) => kMiracleOnlyShortcuts.contains(s.name));
      expect(hidden.length, dropped.length);
    });
  });

  group('modules', () {
    test('workspaces and the scratchpad need Miracle; the clock does not', () {
      expect(workspacesModule.requiresMiracle, isTrue);
      expect(scratchpadModule.requiresMiracle, isTrue);
      expect(clockModule.requiresMiracle, isFalse);
      expect(
        Module.plain(configKey: 'x', builder: (_) => const SizedBox())
            .requiresMiracle,
        isFalse,
      );
    });

    testWidgets('window capture is not offered on another compositor',
        (tester) async {
      List<SelectionMode>? offered;
      Future<void> pumpWith(Map<String, String> environment) async {
        await tester.pumpWidget(
          MiracleScope(
            manager: MiracleManager(environment: environment),
            child: Builder(
              builder: (context) {
                offered = offeredSelectionModes(context);
                return const SizedBox();
              },
            ),
          ),
        );
      }

      await pumpWith({'XDG_CURRENT_DESKTOP': 'sway'});
      expect(offered, isNot(contains(SelectionMode.window)));
      expect(offered, contains(SelectionMode.area));

      await pumpWith({'XDG_CURRENT_DESKTOP': 'mir:miracle-wm'});
      expect(offered, SelectionMode.values);
    });
  });
}
