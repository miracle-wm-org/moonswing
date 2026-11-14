// `org.moonswing.Shell1` against the shell's own stores.
//
// Every method lands on the path a person's click or key already takes —
// `shellActionCallback` for the shortcuts, `SettingsController.open` for the
// overview, `ThemeStore.select`, `TimersStore`, `TodoStore` — so nothing an agent
// does here is a second implementation of anything, and nothing here keeps state
// of its own beyond the leases it takes for the length of one call.

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/app_info.dart' as app_info;
import 'package:moonswing/capture/capture_grab.dart';
import 'package:moonswing/capture/capture_source.dart';
import 'package:moonswing/capture/capture_store.dart';
import 'package:moonswing/capture/capture_targets.dart';
import 'package:moonswing/capture/frame_image.dart';
import 'package:moonswing/capture/window_targets.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/control/control_api.dart';
import 'package:moonswing/control/control_config.dart';
import 'package:moonswing/control/shell_control_server.dart';
import 'package:moonswing/input_trigger/input_trigger_service.dart';
import 'package:moonswing/launcher/app_index.dart';
import 'package:moonswing/launcher/app_search.dart';
import 'package:moonswing/lock/lock_controller.dart';
import 'package:moonswing/miracle_manager.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/quick_panel/audio_devices_store.dart';
import 'package:moonswing/screencast/capture_host.dart';
import 'package:moonswing/theme/theme_store.dart';
import 'package:moonswing/timers/timer_store.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// How long a volume request waits for PulseAudio to report the default
/// device, from a cold lease.
const Duration kControlAudioTimeout = Duration(seconds: 3);

class LiveShellControl implements ShellControl {
  LiveShellControl({required this.miracle});

  final MiracleManager miracle;

  ControlConfig get _config => ControlConfig.fromMap(
        ConfigStore.instance.get<Map<String, dynamic>>(['control']),
      );

  @override
  Map<String, Object> status() {
    final captures = CaptureStore.instance;
    final notifications = NotificationStore.instance;
    return {
      'api': kShellControlApiVersion,
      'theme': ThemeStore.instance.activeName,
      'miracle': !miracle.unsupported && miracle.connection != null,
      'compositor': miracle.unsupported
          ? 'other'
          : (miracle.connection != null ? 'miracle-wm' : 'miracle-wm (not connected)'),
      'do_not_disturb': notifications.silenced,
      'notifications': notifications.items.length,
      'unread_notifications': notifications.unreadCount,
      'recording': captures.recording,
      'locked': LockController.instance.isRequested,
      'timers': TimersStore.instance.entries.length,
      'todo_board': TodoStore.instance.editable,
      'screenshots': _config.screenshots,
    };
  }

  String? _unavailable(ShellAction action) {
    if (action.needsMiracle && miracle.unsupported) return kNotMiracleMessage;
    return null;
  }

  @override
  List<ControlAction> actions() => [
        for (final action in ShellAction.values)
          ControlAction(action, unavailable: _unavailable(action)),
      ];

  @override
  void activate(ShellAction action) {
    final reason = _unavailable(action);
    if (reason != null) throw ShellControlException.unavailable(reason);
    shellActionCallback(action)();
  }

  @override
  void openOverview(String tab) {
    if (!kControlOverviewTabs.contains(tab)) {
      throw ShellControlException.invalidArgs(
          'There is no overview tab "$tab"; it has '
          '${kControlOverviewTabs.join(', ')}.');
    }
    SettingsController.instance.open(
      tab == OverviewTab.settings
          ? const SettingsRoute()
          : SettingsRoute.tab(tab),
    );
  }

  @override
  void openSettings(String category, String module) {
    final key = module.trim();
    if (key.isNotEmpty) {
      if (Module.lookup(key) == null) {
        throw ShellControlException.invalidArgs(
            'There is no module "$key"; modules are '
            '${(Module.registeredKeys.toList()..sort()).join(', ')}.');
      }
      SettingsController.instance.open(SettingsRoute.module(key));
      return;
    }
    final wanted = category.trim().isEmpty ? 'shell' : category.trim();
    if (!kControlSettingsCategories.contains(wanted)) {
      throw ShellControlException.invalidArgs(
          'There is no settings category "$category"; there are '
          '${kControlSettingsCategories.join(', ')}.');
    }
    SettingsController.instance.open(SettingsRoute(category: wanted));
  }

  @override
  List<ControlTheme> themes() => [
        for (final theme in ThemeStore.instance.themes)
          ControlTheme(
            slug: theme.slug,
            name: theme.displayName,
            builtIn: theme.builtIn,
          ),
      ];

  @override
  void setTheme(String slug) {
    final store = ThemeStore.instance;
    if (!store.themes.any((t) => t.slug == slug)) {
      throw ShellControlException.invalidArgs(
          'There is no theme "$slug"; ListThemes names them.');
    }
    store.select(slug);
  }

  @override
  List<ControlTimer> timers() {
    final now = DateTime.now();
    return [
      for (final entry in TimersStore.instance.entries)
        ControlTimer(
          id: entry.id,
          stopwatch: entry.kind == ShellTimerKind.stopwatch,
          label: entry.label ?? '',
          running: entry.running,
          finished: entry.finished,
          reading: entry.displayAt(now),
        ),
    ];
  }

  @override
  int startTimer(Duration duration, String label) =>
      TimersStore.instance.startTimer(duration, label: label);

  @override
  int startStopwatch() => TimersStore.instance.startStopwatch();

  @override
  void timerControl(int id, String operation) {
    final store = TimersStore.instance;
    if (store.entry(id) == null) {
      throw ShellControlException.invalidArgs('There is no timer $id.');
    }
    switch (operation) {
      case 'pause':
        store.pause(id);
      case 'resume':
        store.resume(id);
      case 'reset':
        store.reset(id);
      case 'stop':
        store.stop(id);
    }
  }

  TodoStore _board() {
    final store = TodoStore.instance;
    if (!store.editable) {
      throw const ShellControlException.unavailable(
          'The todo board has not loaded, so it cannot be changed.');
    }
    return store;
  }

  @override
  List<ControlTodo> todos() => [
        for (final item in TodoStore.instance.items)
          ControlTodo(
            id: item.id,
            column: item.column.wireName,
            title: item.title,
            body: item.body,
            due: item.due,
          ),
      ];

  @override
  String addTodo(String title, String body, String column, DateTime? due) {
    final id = _board().add(
      TodoColumn.fromWire(column)!,
      title: title,
      body: body,
      due: due,
    );
    if (id == null) {
      throw const ShellControlException.failed('The card was not added.');
    }
    return id;
  }

  @override
  void moveTodo(String id, String column) {
    final board = _board();
    if (board.item(id) == null) {
      throw ShellControlException.invalidArgs('There is no card "$id".');
    }
    board.move(id, TodoColumn.fromWire(column)!);
  }

  @override
  void deleteTodo(String id) {
    final board = _board();
    if (board.item(id) == null) {
      throw ShellControlException.invalidArgs('There is no card "$id".');
    }
    board.delete(id);
  }

  @override
  String addNote(String title, String body) {
    final id = _board().addNote(title: title, body: body);
    if (id == null) {
      throw const ShellControlException.failed('The note was not added.');
    }
    return id;
  }

  @override
  List<ControlNotification> notifications() => [
        for (final item in NotificationStore.instance.items)
          ControlNotification(
            id: item.id,
            appName: item.appName,
            summary: item.summary,
            body: item.body,
            arrivedAt: item.arrivedAt,
            read: item.read,
          ),
      ];

  @override
  void dismissNotification(int id) {
    final store = NotificationStore.instance;
    if (id == 0) {
      store.dismissAll();
      return;
    }
    if (!store.items.any((n) => n.id == id)) {
      throw ShellControlException.invalidArgs('There is no notification $id.');
    }
    store.dismiss(id);
  }

  @override
  void setDoNotDisturb(bool value) =>
      NotificationStore.instance.setSilenced(value);

  @override
  List<ControlApp> searchApps(String query, int limit) {
    final index = AppIndex.instance;
    if (index.apps.isEmpty) {
      throw const ShellControlException.unavailable(
          'The application index has not been built yet.');
    }
    return [
      for (final entry in rankApps(index.searchable, query, limit: limit))
        ControlApp(
          id: entry.id,
          name: entry.name,
          description: entry.genericName,
        ),
    ];
  }

  @override
  void launchApp(String id) {
    final index = AppIndex.instance;
    final wanted = id.endsWith('.desktop')
        ? id.substring(0, id.length - '.desktop'.length)
        : id;
    index.acquire();
    try {
      app_info.AppEntry? match;
      for (final entry in index.apps) {
        if (entry.id == wanted) {
          match = entry;
          break;
        }
      }
      if (match == null) {
        throw ShellControlException.invalidArgs(
            'There is no application "$id"; SearchApps finds their ids.');
      }
      if (!app_info.launchApp(match.appInfo)) {
        throw ShellControlException.failed('${match.name} did not start.');
      }
    } finally {
      index.release();
    }
  }

  /// Runs [body] under a lease on the default audio devices, once PulseAudio
  /// has reported them.
  Future<T> _withAudio<T>(
      FutureOr<T> Function(AudioDevicesStore store) body) async {
    final store = AudioDevicesStore.instance;
    store.acquire();
    try {
      if (store.status != AudioDevicesStatus.ready) {
        final ready = Completer<void>();
        void check() {
          if (ready.isCompleted) return;
          if (store.status == AudioDevicesStatus.ready ||
              store.status == AudioDevicesStatus.unavailable) {
            ready.complete();
          }
        }

        store.addListener(check);
        try {
          check();
          await ready.future.timeout(kControlAudioTimeout, onTimeout: () {});
        } finally {
          store.removeListener(check);
        }
      }
      if (store.status != AudioDevicesStatus.ready ||
          store.current(AudioDirection.output) == null) {
        throw ShellControlException.unavailable(store.error.isNotEmpty
            ? store.error
            : 'The shell cannot reach the sound server.');
      }
      return await body(store);
    } finally {
      store.release();
    }
  }

  @override
  Future<({double volume, bool muted})> volume() => _withAudio((store) {
        final device = store.current(AudioDirection.output)!;
        return (volume: device.volume, muted: device.muted);
      });

  @override
  Future<void> setVolume(double volume) =>
      _withAudio((store) => store.setVolume(AudioDirection.output, volume));

  @override
  Future<void> setMuted(bool muted) =>
      _withAudio((store) => store.setMuted(AudioDirection.output, muted));

  @override
  Future<Uint8List> screenshot(String output, int maxWidth) async {
    if (!_config.screenshots) {
      throw const ShellControlException.unavailable(
          'Screenshots over the control interface are switched off '
          '([control] screenshots = false).');
    }
    final captures = CaptureStore.instance;
    final tree = await captures.readTree();
    if (tree == null) {
      throw const ShellControlException.unavailable(
          'The shell finds the screens through Miracle WM\'s window tree, '
          'and is not connected to it.');
    }
    final screens = collectOutputs(tree);
    final ScreenOutput? screen = output.trim().isEmpty
        ? (focusedOutput(tree) ?? (screens.isEmpty ? null : screens.first))
        : screens.where((s) => s.name == output.trim()).firstOrNull;
    if (screen == null) {
      throw ShellControlException.invalidArgs(output.trim().isEmpty
          ? 'No screen is active.'
          : 'There is no active screen "$output"; there are '
              '${screens.map((s) => s.name).join(', ')}.');
    }
    final connection = CaptureHost.connect();
    if (connection == null) {
      throw const ShellControlException.unavailable(
          'The shell cannot reach the compositor to capture the screen.');
    }
    final FrameBytes frame;
    try {
      frame = await grabFrame(
        connection,
        OutputCapture(
          connector: screen.name,
          outputSize: screen.size,
          outputOrigin: CapturePoint(screen.rect.x, screen.rect.y),
        ),
        paintCursors: captures.screenshotConfig.showCursor,
      );
    } on CaptureException catch (e) {
      throw ShellControlException.failed(e.message);
    }
    final png = await encodePng(frame, maxWidth: maxWidth);
    if (png == null) {
      throw const ShellControlException.failed(
          'The captured frame could not be encoded.');
    }
    return png;
  }
}

/// Exports `org.moonswing.Shell` on the session bus.
///
/// `ShellServices`' contract: an unreachable bus throws; another shell already
/// owning the name is a graceful decline, logged and returned from.
Future<void> startShellControlService(ShellControl control) async {
  final client = DBusClient.session();
  try {
    // Export before requesting the name, so a call arriving the instant the
    // name is granted already finds the object.
    await client.registerObject(ShellControlServer(control));
    final reply = await client.requestName(kShellControlBusName,
        flags: {DBusRequestNameFlag.doNotQueue});
    if (reply != DBusRequestNameReply.primaryOwner &&
        reply != DBusRequestNameReply.alreadyOwner) {
      debugPrint('control: $kShellControlBusName is owned by another shell; '
          'this one will not answer it');
      await client.close();
      return;
    }
    debugPrint('control: serving $kShellControlBusName');
  } catch (_) {
    unawaited(client.close());
    rethrow;
  }
}
