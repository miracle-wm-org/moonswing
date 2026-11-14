// `org.moonswing.Shell1` on the bus: the marshalling, and nothing else.
//
// What each method *does* is [ShellControl]'s — `live_shell_control.dart` in
// the shell, a fake in `test/shell_control_test.dart` — so this file is the
// interface table, the argument checks and the reply shapes, and it is
// Flutter-free for `dbus_service_object.dart`'s reason.
library;

import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import 'package:moonswing/control/control_api.dart';
import 'package:moonswing/dbus_service_object.dart';

/// A refusal with a D-Bus error name from [ShellControlError] and a sentence.
class ShellControlException implements Exception {
  const ShellControlException(this.name, this.message);

  const ShellControlException.invalidArgs(this.message)
      : name = ShellControlError.invalidArgs;

  const ShellControlException.unavailable(this.message)
      : name = ShellControlError.unavailable;

  const ShellControlException.failed(this.message)
      : name = ShellControlError.failed;

  final String name;
  final String message;

  @override
  String toString() => 'ShellControlException($name): $message';
}

/// One row of `ListActions`.
class ControlAction {
  const ControlAction(this.action, {this.unavailable});

  final ShellAction action;

  /// Why it would do nothing here, or null when it would work.
  final String? unavailable;
}

class ControlTheme {
  const ControlTheme({
    required this.slug,
    required this.name,
    required this.builtIn,
  });

  final String slug;
  final String name;
  final bool builtIn;
}

class ControlTimer {
  const ControlTimer({
    required this.id,
    required this.stopwatch,
    required this.label,
    required this.running,
    required this.finished,
    required this.reading,
  });

  final int id;
  final bool stopwatch;
  final String label;
  final bool running;
  final bool finished;

  /// Time left for a countdown, time spent for a stopwatch.
  final Duration reading;
}

class ControlTodo {
  const ControlTodo({
    required this.id,
    required this.column,
    required this.title,
    required this.body,
    this.due,
  });

  final String id;

  /// One of [kControlTodoColumns].
  final String column;
  final String title;
  final String body;
  final DateTime? due;
}

class ControlNotification {
  const ControlNotification({
    required this.id,
    required this.appName,
    required this.summary,
    required this.body,
    required this.arrivedAt,
    required this.read,
  });

  final int id;
  final String appName;
  final String summary;
  final String body;
  final DateTime arrivedAt;
  final bool read;
}

class ControlApp {
  const ControlApp({
    required this.id,
    required this.name,
    required this.description,
  });

  /// The desktop entry id without `.desktop`, e.g. `org.gnome.Nautilus`.
  final String id;
  final String name;

  /// The generic name, e.g. "Web Browser", or empty.
  final String description;
}

/// What the shell does for each method. Every member may throw a
/// [ShellControlException]; anything else thrown is answered as
/// [ShellControlError.failed] with its text.
abstract interface class ShellControl {
  Map<String, Object> status();

  List<ControlAction> actions();
  void activate(ShellAction action);

  void openOverview(String tab);
  void openSettings(String category, String module);

  List<ControlTheme> themes();
  void setTheme(String slug);

  List<ControlTimer> timers();
  int startTimer(Duration duration, String label);
  int startStopwatch();
  void timerControl(int id, String operation);

  List<ControlTodo> todos();
  String addTodo(String title, String body, String column, DateTime? due);
  void moveTodo(String id, String column);
  void deleteTodo(String id);
  String addNote(String title, String body);

  List<ControlNotification> notifications();
  void dismissNotification(int id);
  void setDoNotDisturb(bool value);

  List<ControlApp> searchApps(String query, int limit);
  void launchApp(String id);

  Future<({double volume, bool muted})> volume();
  Future<void> setVolume(double volume);
  Future<void> setMuted(bool muted);

  /// A PNG of [output] (a connector name, or empty for the focused screen),
  /// no wider than [maxWidth] when that is not zero.
  ///
  /// The bytes, never a path: a client trusting a path would read — and, to
  /// clean up, delete — whatever file whoever owns the bus name named.
  Future<Uint8List> screenshot(String output, int maxWidth);
}

/// The exported object.
class ShellControlServer extends DBusServiceObject {
  ShellControlServer(this._control)
      : super(DBusObjectPath(kShellControlObjectPath));

  final ShellControl _control;

  static DBusIntrospectArgument _in(String sig, String name) =>
      DBusIntrospectArgument(DBusSignature(sig), DBusArgumentDirection.in_,
          name: name);

  static DBusIntrospectArgument _out(String sig, String name) =>
      DBusIntrospectArgument(DBusSignature(sig), DBusArgumentDirection.out,
          name: name);

  /// One method: its signature checked, its handler's throw turned into a
  /// named error.
  DBusServiceMethod _method(
    String signature,
    Future<List<DBusValue>> Function(List<DBusValue> values) body, {
    List<DBusIntrospectArgument> args = const [],
  }) {
    return DBusServiceMethod(
      (call) async {
        if (call.signature != DBusSignature(signature)) {
          return DBusMethodErrorResponse(ShellControlError.invalidArgs, [
            DBusString('Expected arguments ($signature), '
                'got (${call.signature.value}).'),
          ]);
        }
        try {
          return DBusMethodSuccessResponse(await body(call.values));
        } on ShellControlException catch (e) {
          return DBusMethodErrorResponse(e.name, [DBusString(e.message)]);
        } catch (e) {
          return DBusMethodErrorResponse(
              ShellControlError.failed, [DBusString('$e')]);
        }
      },
      args: args,
    );
  }

  @override
  late final List<DBusServiceInterface> interfaces = [
    DBusServiceInterface(
      kShellControlInterface,
      methods: {
        'GetStatus': _method(
          '',
          (_) async => [_variantDict(_control.status())],
          args: [_out('a{sv}', 'status')],
        ),
        'ListActions': _method(
          '',
          (_) async => [
            DBusArray(DBusSignature('(ssbs)'), [
              for (final row in _control.actions())
                DBusStruct([
                  DBusString(row.action.id),
                  DBusString(row.action.description),
                  DBusBoolean(row.unavailable == null),
                  DBusString(row.unavailable ?? ''),
                ]),
            ]),
          ],
          args: [_out('a(ssbs)', 'actions')],
        ),
        'Activate': _method(
          's',
          (v) async {
            final id = _string(v[0]);
            final action = ShellAction.fromId(id);
            if (action == null) {
              throw ShellControlException.invalidArgs(
                  'There is no action "$id". ListActions names them: '
                  '${ShellAction.values.map((a) => a.id).join(', ')}.');
            }
            _control.activate(action);
            return [];
          },
          args: [_in('s', 'action')],
        ),
        'OpenOverview': _method(
          's',
          (v) async {
            _control.openOverview(_string(v[0]));
            return [];
          },
          args: [_in('s', 'tab')],
        ),
        'OpenSettings': _method(
          'ss',
          (v) async {
            _control.openSettings(_string(v[0]), _string(v[1]));
            return [];
          },
          args: [_in('s', 'category'), _in('s', 'module')],
        ),
        'ListThemes': _method(
          '',
          (_) async => [
            DBusArray(DBusSignature('(ssb)'), [
              for (final theme in _control.themes())
                DBusStruct([
                  DBusString(theme.slug),
                  DBusString(theme.name),
                  DBusBoolean(theme.builtIn),
                ]),
            ]),
          ],
          args: [_out('a(ssb)', 'themes')],
        ),
        'SetTheme': _method(
          's',
          (v) async {
            _control.setTheme(_string(v[0]));
            return [];
          },
          args: [_in('s', 'slug')],
        ),
        'ListTimers': _method(
          '',
          (_) async => [
            DBusArray(DBusSignature('(ubsbbt)'), [
              for (final timer in _control.timers())
                DBusStruct([
                  DBusUint32(timer.id),
                  DBusBoolean(timer.stopwatch),
                  DBusString(timer.label),
                  DBusBoolean(timer.running),
                  DBusBoolean(timer.finished),
                  DBusUint64(timer.reading.inMilliseconds),
                ]),
            ]),
          ],
          args: [_out('a(ubsbbt)', 'timers')],
        ),
        'StartTimer': _method(
          'ts',
          (v) async {
            final seconds = (v[0] as DBusUint64).value;
            if (seconds == 0) {
              throw const ShellControlException.invalidArgs(
                  'A timer needs a duration of at least one second.');
            }
            return [
              DBusUint32(_control.startTimer(
                  Duration(seconds: seconds), _string(v[1]))),
            ];
          },
          args: [_in('t', 'seconds'), _in('s', 'label'), _out('u', 'id')],
        ),
        'StartStopwatch': _method(
          '',
          (_) async => [DBusUint32(_control.startStopwatch())],
          args: [_out('u', 'id')],
        ),
        'TimerControl': _method(
          'us',
          (v) async {
            final operation = _string(v[1]);
            if (!kControlTimerOperations.contains(operation)) {
              throw ShellControlException.invalidArgs(
                  'Unknown timer operation "$operation"; expected one of '
                  '${kControlTimerOperations.join(', ')}.');
            }
            _control.timerControl((v[0] as DBusUint32).value, operation);
            return [];
          },
          args: [_in('u', 'id'), _in('s', 'operation')],
        ),
        'ListTodos': _method(
          '',
          (_) async => [
            DBusArray(DBusSignature('(sssss)'), [
              for (final todo in _control.todos())
                DBusStruct([
                  DBusString(todo.id),
                  DBusString(todo.column),
                  DBusString(todo.title),
                  DBusString(todo.body),
                  DBusString(todo.due == null ? '' : formatControlDate(todo.due!)),
                ]),
            ]),
          ],
          args: [_out('a(sssss)', 'todos')],
        ),
        'AddTodo': _method(
          'ssss',
          (v) async {
            final title = _string(v[0]).trim();
            if (title.isEmpty) {
              throw const ShellControlException.invalidArgs(
                  'A card needs a title.');
            }
            final column = _column(_string(v[2]), fallback: 'inbox');
            final dueText = _string(v[3]).trim();
            DateTime? due;
            if (dueText.isNotEmpty) {
              due = DateTime.tryParse(dueText);
              if (due == null) {
                throw ShellControlException.invalidArgs(
                    'Could not read the due date "$dueText"; '
                    'write it as YYYY-MM-DD.');
              }
            }
            return [
              DBusString(_control.addTodo(title, _string(v[1]), column, due)),
            ];
          },
          args: [
            _in('s', 'title'),
            _in('s', 'body'),
            _in('s', 'column'),
            _in('s', 'due'),
            _out('s', 'id'),
          ],
        ),
        'MoveTodo': _method(
          'ss',
          (v) async {
            _control.moveTodo(_string(v[0]), _column(_string(v[1])));
            return [];
          },
          args: [_in('s', 'id'), _in('s', 'column')],
        ),
        'DeleteTodo': _method(
          's',
          (v) async {
            _control.deleteTodo(_string(v[0]));
            return [];
          },
          args: [_in('s', 'id')],
        ),
        'AddNote': _method(
          'ss',
          (v) async {
            final body = _string(v[1]);
            if (body.trim().isEmpty && _string(v[0]).trim().isEmpty) {
              throw const ShellControlException.invalidArgs(
                  'A note needs a title or some text.');
            }
            return [DBusString(_control.addNote(_string(v[0]), body))];
          },
          args: [_in('s', 'title'), _in('s', 'body'), _out('s', 'id')],
        ),
        'ListNotifications': _method(
          '',
          (_) async => [
            DBusArray(DBusSignature('(usssxb)'), [
              for (final n in _control.notifications())
                DBusStruct([
                  DBusUint32(n.id),
                  DBusString(n.appName),
                  DBusString(n.summary),
                  DBusString(n.body),
                  DBusInt64(n.arrivedAt.millisecondsSinceEpoch),
                  DBusBoolean(n.read),
                ]),
            ]),
          ],
          args: [_out('a(usssxb)', 'notifications')],
        ),
        'DismissNotification': _method(
          'u',
          (v) async {
            _control.dismissNotification((v[0] as DBusUint32).value);
            return [];
          },
          args: [_in('u', 'id')],
        ),
        'SetDoNotDisturb': _method(
          'b',
          (v) async {
            _control.setDoNotDisturb((v[0] as DBusBoolean).value);
            return [];
          },
          args: [_in('b', 'enabled')],
        ),
        'SearchApps': _method(
          'su',
          (v) async {
            final limit = (v[1] as DBusUint32).value;
            return [
              DBusArray(DBusSignature('(sss)'), [
                for (final app in _control.searchApps(
                    _string(v[0]), limit == 0 ? 20 : limit.clamp(1, 200)))
                  DBusStruct([
                    DBusString(app.id),
                    DBusString(app.name),
                    DBusString(app.description),
                  ]),
              ]),
            ];
          },
          args: [_in('s', 'query'), _in('u', 'limit'), _out('a(sss)', 'apps')],
        ),
        'LaunchApp': _method(
          's',
          (v) async {
            _control.launchApp(_string(v[0]));
            return [];
          },
          args: [_in('s', 'id')],
        ),
        'GetVolume': _method(
          '',
          (_) async {
            final reading = await _control.volume();
            return [DBusDouble(reading.volume), DBusBoolean(reading.muted)];
          },
          args: [_out('d', 'volume'), _out('b', 'muted')],
        ),
        'SetVolume': _method(
          'd',
          (v) async {
            final volume = (v[0] as DBusDouble).value;
            if (volume.isNaN || volume < 0 || volume > 1) {
              throw const ShellControlException.invalidArgs(
                  'The volume is a fraction from 0.0 to 1.0.');
            }
            await _control.setVolume(volume);
            return [];
          },
          args: [_in('d', 'volume')],
        ),
        'SetMuted': _method(
          'b',
          (v) async {
            await _control.setMuted((v[0] as DBusBoolean).value);
            return [];
          },
          args: [_in('b', 'muted')],
        ),
        'Screenshot': _method(
          'su',
          (v) async => [
            DBusArray.byte(await _control.screenshot(
                _string(v[0]), (v[1] as DBusUint32).value)),
          ],
          args: [_in('s', 'output'), _in('u', 'max_width'), _out('ay', 'png')],
        ),
      },
    ),
  ];

  static String _string(DBusValue value) => (value as DBusString).value;

  static String _column(String column, {String? fallback}) {
    final wanted = column.trim().isEmpty && fallback != null ? fallback : column;
    if (!kControlTodoColumns.contains(wanted)) {
      throw ShellControlException.invalidArgs(
          'There is no column "$column"; the board has '
          '${kControlTodoColumns.join(', ')}.');
    }
    return wanted;
  }

  static DBusDict _variantDict(Map<String, Object> map) => DBusDict.stringVariant({
        for (final entry in map.entries) entry.key: _toDBus(entry.value),
      });

  static DBusValue _toDBus(Object value) => switch (value) {
        final bool b => DBusBoolean(b),
        final int i => DBusInt64(i),
        final double d => DBusDouble(d),
        final String s => DBusString(s),
        final List<String> l => DBusArray.string(l),
        _ => DBusString('$value'),
      };
}

/// A date as the interface writes one, `YYYY-MM-DD`.
String formatControlDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
      '${two(date.day)}';
}
