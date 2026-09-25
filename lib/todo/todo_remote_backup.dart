// Backup servers for the todo board: somewhere other than this machine that
// the backup file is sent to, on a schedule, and read back from on request.
//
// The protocol is WebDAV — a `PUT` of the backup file into a folder — because
// it is what the servers people already have speak: Nextcloud and ownCloud,
// most NAS boxes (Synology, QNAP, TrueNAS), Fastmail and a dozen hosted file
// services, `rclone serve webdav`, and any web server with a WebDAV module.
// Nothing about it is WebDAV-only, either: an endpoint that takes a `PUT` and
// answers the same file to a `GET` works too. There may be several, each
// independent of the others.
//
// What is sent is exactly the local backup file (`todo_backup.dart`), so there
// is one format to restore from wherever a copy came from. A server is sent a
// new copy at most once per its [BackupFrequency], and only when the board has
// changed since the last copy it was sent — an idle shell with an unchanged
// board uploads nothing, ever. With [BackupServer.keepDaily] each upload also
// writes a copy named for the day, so a board emptied by mistake and uploaded
// is not the only copy the server holds.
//
// The list, the passwords and each server's last result are one file in the
// XDG *state* directory at 0600 — not `config.toml`, for the reasons
// `github/github_token_store.dart` gives for the GitHub token.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:moonswing/native/libc.dart';
import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The file a folder URL is given.
const String kRemoteBackupFileName = 'moonswing-todo.json';

/// How long one request may take before it counts as unreachable.
const Duration kRemoteBackupTimeout = Duration(seconds: 30);

/// How soon a failed upload is tried again, if that is sooner than the
/// server's own frequency: a laptop that was offline for one attempt should
/// not wait a day for the next.
const Duration kRemoteBackupRetry = Duration(minutes: 15);

/// How often a server is sent the board, at most.
enum BackupFrequency {
  hourly('hourly', 'Every hour', Duration(hours: 1)),
  sixHours('six_hours', 'Every 6 hours', Duration(hours: 6)),
  daily('daily', 'Once a day', Duration(days: 1));

  const BackupFrequency(this.wireName, this.label, this.interval);

  final String wireName;
  final String label;
  final Duration interval;

  static BackupFrequency fromWire(Object? value) {
    for (final f in values) {
      if (f.wireName == value) return f;
    }
    return hourly;
  }
}

/// One backup server, as the user configured it.
@immutable
class BackupServer {
  const BackupServer({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.enabled = true,
    this.frequency = BackupFrequency.hourly,
    this.keepDaily = true,
  });

  final String id;

  /// What the user calls it. Falls back to the host.
  final String name;

  /// A folder (the file is [kRemoteBackupFileName] inside it) or the full URL
  /// of a `.json` file.
  final String url;
  final String username;
  final String password;
  final bool enabled;
  final BackupFrequency frequency;

  /// Whether each upload also writes a copy named for the day.
  final bool keepDaily;

  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    return Uri.tryParse(url)?.host ?? url;
  }

  /// The URL the backup is written to and read from, or null when [url] is
  /// not an `http(s)` address.
  Uri? get fileUri => remoteBackupFileUri(url);

  BackupServer copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool? enabled,
    BackupFrequency? frequency,
    bool? keepDaily,
  }) => BackupServer(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    enabled: enabled ?? this.enabled,
    frequency: frequency ?? this.frequency,
    keepDaily: keepDaily ?? this.keepDaily,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'username': username,
    'password': password,
    'enabled': enabled,
    'frequency': frequency.wireName,
    'keep_daily': keepDaily,
  };

  static BackupServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final url = json['url'];
    if (id is! String || id.isEmpty || url is! String) return null;
    String text(Object? v) => v is String ? v : '';
    return BackupServer(
      id: id,
      name: text(json['name']),
      url: url,
      username: text(json['username']),
      password: text(json['password']),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      frequency: BackupFrequency.fromWire(json['frequency']),
      keepDaily: json['keep_daily'] is bool ? json['keep_daily'] as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupServer &&
      other.id == id &&
      other.name == name &&
      other.url == url &&
      other.username == username &&
      other.password == password &&
      other.enabled == enabled &&
      other.frequency == frequency &&
      other.keepDaily == keepDaily;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    url,
    username,
    password,
    enabled,
    frequency,
    keepDaily,
  );
}

/// How a server's last attempt went.
@immutable
class BackupServerStatus {
  const BackupServerStatus({
    this.lastAttempt,
    this.lastSuccess,
    this.lastError,
    this.lastDigest,
  });

  final DateTime? lastAttempt;
  final DateTime? lastSuccess;

  /// Why the last attempt failed, or null when it did not.
  final String? lastError;

  /// [todoBackupDigest] of what the server was last sent.
  final String? lastDigest;

  Map<String, Object?> toJson() => {
    if (lastAttempt != null)
      'last_attempt': lastAttempt!.toUtc().toIso8601String(),
    if (lastSuccess != null)
      'last_success': lastSuccess!.toUtc().toIso8601String(),
    if (lastError != null) 'last_error': lastError,
    if (lastDigest != null) 'last_digest': lastDigest,
  };

  static BackupServerStatus fromJson(Object? json) {
    if (json is! Map) return const BackupServerStatus();
    DateTime? moment(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return BackupServerStatus(
      lastAttempt: moment(json['last_attempt']),
      lastSuccess: moment(json['last_success']),
      lastError: json['last_error'] is String
          ? json['last_error'] as String
          : null,
      lastDigest: json['last_digest'] is String
          ? json['last_digest'] as String
          : null,
    );
  }
}

/// The file URL for a server's [url]: the URL itself when it names a `.json`
/// file, [kRemoteBackupFileName] inside it otherwise. Null for anything that is
/// not an absolute `http` or `https` address.
Uri? remoteBackupFileUri(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null ||
      !(parsed.scheme == 'https' || parsed.scheme == 'http') ||
      parsed.host.isEmpty) {
    return null;
  }
  if (parsed.path.toLowerCase().endsWith('.json')) return parsed;
  final folder = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
  return parsed.replace(path: '$folder$kRemoteBackupFileName');
}

/// The dated copy beside [file]: `moonswing-todo-2026-09-25.json`.
Uri remoteBackupDailyUri(Uri file, DateTime day) {
  final path = file.path;
  final stem = path.substring(0, path.length - '.json'.length);
  return file.replace(path: '$stem-${formatDate(day)}.json');
}

/// Whether [url] would send a password unencrypted to another machine.
bool remoteBackupIsInsecure(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || parsed.scheme != 'http') return false;
  const local = {'localhost', '127.0.0.1', '::1', '[::1]'};
  return !local.contains(parsed.host);
}

/// Why a request to a server failed, in words for the user.
class RemoteBackupException implements Exception {
  const RemoteBackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The two requests a server is asked, over HTTP.
class RemoteBackupTransport {
  RemoteBackupTransport({http.Client? client}) : _client = client;

  final http.Client? _client;

  Map<String, String> _headers(BackupServer server) => {
    if (server.username.isNotEmpty || server.password.isNotEmpty)
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${server.username}:${server.password}'))}',
  };

  Future<http.Response> _send(
    String method,
    Uri url,
    BackupServer server, {
    String? body,
  }) async {
    final request = http.Request(method, url)..headers.addAll(_headers(server));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    final client = _client ?? http.Client();
    try {
      final streamed = await client.send(request).timeout(kRemoteBackupTimeout);
      return await http.Response.fromStream(
        streamed,
      ).timeout(kRemoteBackupTimeout);
    } on TimeoutException {
      throw RemoteBackupException('${url.host} did not answer in time.');
    } on RemoteBackupException {
      rethrow;
    } catch (e) {
      throw RemoteBackupException('Could not reach ${url.host}: $e');
    } finally {
      if (_client == null) client.close();
    }
  }

  static String _refusal(
    Uri url,
    http.Response response,
  ) => switch (response.statusCode) {
    401 || 403 =>
      '${url.host} refused the user name or password '
          '(${response.statusCode}).',
    404 => '${url.host} has no such folder (404).',
    507 => '${url.host} is out of space (507).',
    _ =>
      '${url.host} answered ${response.statusCode}'
          '${response.reasonPhrase == null ? '' : ' ${response.reasonPhrase}'}.',
  };

  static bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// Writes [contents] to [url]. A missing folder (409, or 404 from some
  /// servers) is made once with `MKCOL` and the write tried again — one level
  /// only, so a mistyped path does not grow a tree on somebody's server.
  Future<void> put(BackupServer server, Uri url, String contents) async {
    var response = await _send('PUT', url, server, body: contents);
    if (response.statusCode == 409 || response.statusCode == 404) {
      final folder = url.replace(
        path: url.path.substring(0, url.path.lastIndexOf('/') + 1),
      );
      final made = await _send('MKCOL', folder, server);
      // 405: the folder is there already, and something else was wrong.
      if (_ok(made) || made.statusCode == 405) {
        response = await _send('PUT', url, server, body: contents);
      }
    }
    if (!_ok(response)) throw RemoteBackupException(_refusal(url, response));
  }

  /// Reads [url].
  Future<String> get(BackupServer server, Uri url) async {
    final response = await _send('GET', url, server);
    if (response.statusCode == 404) {
      throw RemoteBackupException('There is no backup at $url yet.');
    }
    if (!_ok(response)) throw RemoteBackupException(_refusal(url, response));
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

/// The backup servers, their schedule, and what each last did.
///
/// One timer for the machine, and only while some enabled server is owed a
/// copy it has not had — see [_schedule]. Times are wall-clock moments
/// compared against now, never counted down, so a suspend or a restart does
/// not reset anybody's hour.
class TodoRemoteBackup extends ChangeNotifier {
  TodoRemoteBackup._({
    required TodoStore store,
    String? directory,
    http.Client? client,
    DateTime Function()? now,
    bool autoTimers = true,
  }) : _store = store,
       _directory = directory,
       _transport = RemoteBackupTransport(client: client),
       _now = now ?? DateTime.now,
       _autoTimers = autoTimers;

  static final TodoRemoteBackup instance = TodoRemoteBackup._(
    store: TodoStore.instance,
  );

  /// Over [directory], with [client] for every request and no timer — a test
  /// calls [runDue] itself.
  @visibleForTesting
  factory TodoRemoteBackup.forTesting({
    required TodoStore store,
    required String directory,
    required http.Client client,
    DateTime Function()? now,
  }) => TodoRemoteBackup._(
    store: store,
    directory: directory,
    client: client,
    now: now,
    autoTimers: false,
  );

  final TodoStore _store;
  final String? _directory;
  final RemoteBackupTransport _transport;
  final DateTime Function() _now;
  final bool _autoTimers;

  List<BackupServer> _servers = const [];
  Map<String, BackupServerStatus> _status = const {};
  final Set<String> _busy = {};
  bool _loaded = false;
  bool _started = false;
  String? _fileError;
  Timer? _timer;
  bool _disposed = false;

  /// Uploads in flight run one after another; a second [runDue] while one is
  /// running finds nothing left owed.
  Future<void> _running = Future.value();

  String get directory {
    final override = _directory;
    if (override != null) return override;
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing';
    return '${env['HOME'] ?? '.'}/.local/state/moonswing';
  }

  /// The list, the passwords and the results.
  String get path => '$directory/todo-backup-servers.json';

  List<BackupServer> get servers => _servers;
  bool get loaded => _loaded;

  /// Why the server list could not be read or saved, or null.
  String? get fileError => _fileError;

  BackupServerStatus status(String id) =>
      _status[id] ?? const BackupServerStatus();

  /// Whether a request to [id] is under way.
  bool busy(String id) => _busy.contains(id);

  /// Whether any enabled server's last attempt failed.
  bool get anyFailing =>
      _servers.any((s) => s.enabled && _status[s.id]?.lastError != null);

  /// Reads the list and starts listening for new boards. What `main()` calls
  /// once; later calls are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _store.onBackupWritten = (_) => _schedule();
    await load();
  }

  Future<void> load() async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final rows = json is Map ? json['servers'] : null;
        final servers = <BackupServer>[];
        final status = <String, BackupServerStatus>{};
        if (rows is List) {
          for (final row in rows) {
            final server = BackupServer.fromJson(row);
            if (server == null || status.containsKey(server.id)) continue;
            servers.add(server);
            status[server.id] = BackupServerStatus.fromJson(
              (row as Map)['status'],
            );
          }
        }
        _servers = List.unmodifiable(servers);
        _status = status;
      }
      _fileError = null;
    } catch (e) {
      _fileError = 'Could not read the backup servers from $path: $e';
    }
    _loaded = true;
    _notify();
    _schedule();
  }

  Future<void> _save() async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      chmodPath(directory, 0x1C0); // 0700
      final contents = const JsonEncoder.withIndent('  ').convert({
        'servers': [
          for (final s in _servers)
            {...s.toJson(), 'status': status(s.id).toJson()},
        ],
      });
      final temporary = File('$path.tmp');
      await temporary.writeAsString(contents, flush: true);
      // Narrowed before it takes the real name: it holds passwords.
      chmodPath(temporary.path, 0x180); // 0600
      await temporary.rename(path);
      if (_fileError != null) {
        _fileError = null;
        _notify();
      }
    } catch (e) {
      _fileError = 'Could not save the backup servers to $path: $e';
      _notify();
    }
  }

  String _newId() => _now().microsecondsSinceEpoch.toRadixString(36);

  /// Adds a server and returns it. It is sent the board straight away.
  Future<BackupServer> add({
    required String name,
    required String url,
    String username = '',
    String password = '',
    BackupFrequency frequency = BackupFrequency.hourly,
    bool keepDaily = true,
  }) async {
    final server = BackupServer(
      id: _newId(),
      name: name.trim(),
      url: url.trim(),
      username: username,
      password: password,
      frequency: frequency,
      keepDaily: keepDaily,
    );
    _servers = List.unmodifiable([..._servers, server]);
    _notify();
    await _save();
    _schedule();
    return server;
  }

  /// Replaces a server's settings. A new address is a new destination, so
  /// what the old one was sent says nothing about it.
  Future<void> update(BackupServer server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index < 0) return;
    final old = _servers[index];
    if (old == server) return;
    _servers = List.unmodifiable([
      for (final s in _servers) s.id == server.id ? server : s,
    ]);
    if (old.url.trim() != server.url.trim() ||
        old.username != server.username) {
      _status = {..._status}..remove(server.id);
    }
    _notify();
    await _save();
    _schedule();
  }

  Future<void> remove(String id) async {
    _servers = List.unmodifiable([
      for (final s in _servers)
        if (s.id != id) s,
    ]);
    _status = {..._status}..remove(id);
    _notify();
    await _save();
    _schedule();
  }

  /// Sends the board to [id] now, whatever the schedule says. Returns why it
  /// failed, or null.
  Future<String?> backUpNow(String id) async {
    final server = _server(id);
    if (server == null) return 'That server is gone.';
    final contents = _store.backupContents;
    if (contents == null) {
      return 'The board has not been read, so there is nothing to send.';
    }
    return _upload(server, contents);
  }

  /// Reads the backup [id] holds. Throws [RemoteBackupException].
  Future<TodoBackup> fetch(String id) async {
    final server = _server(id);
    final url = server?.fileUri;
    if (server == null || url == null) {
      throw const RemoteBackupException('That server has no valid address.');
    }
    _busy.add(id);
    _notify();
    try {
      final source = await _transport.get(server, url);
      try {
        return decodeTodoBackup(source);
      } on TodoFormatException catch (e) {
        throw RemoteBackupException('What $url holds is not a board: $e');
      }
    } finally {
      _busy.remove(id);
      _notify();
    }
  }

  BackupServer? _server(String id) {
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<String?> _upload(BackupServer server, String contents) async {
    final url = server.fileUri;
    final at = _now();
    String? error;
    if (url == null) {
      error = '“${server.url}” is not an http or https address.';
    } else {
      _busy.add(server.id);
      _notify();
      try {
        await _transport.put(server, url, contents);
        if (server.keepDaily) {
          await _transport.put(
            server,
            remoteBackupDailyUri(url, dateOnly(at)),
            contents,
          );
        }
      } on RemoteBackupException catch (e) {
        error = e.message;
      } finally {
        _busy.remove(server.id);
      }
    }
    final previous = status(server.id);
    _status = {
      ..._status,
      server.id: BackupServerStatus(
        lastAttempt: at,
        lastSuccess: error == null ? at : previous.lastSuccess,
        lastError: error,
        lastDigest: error == null
            ? todoBackupDigest(contents)
            : previous.lastDigest,
      ),
    };
    _notify();
    // A server removed while its upload was in flight stays removed.
    if (_server(server.id) != null) await _save();
    return error;
  }

  /// When [server] is next owed the board [digest], or null when it has it.
  DateTime? _dueAt(BackupServer server, String digest) {
    if (!server.enabled || server.fileUri == null) return null;
    final s = status(server.id);
    if (s.lastDigest == digest && s.lastError == null) return null;
    final last = s.lastAttempt;
    if (last == null) return _now();
    var wait = server.frequency.interval;
    if (s.lastError != null && kRemoteBackupRetry < wait) {
      wait = kRemoteBackupRetry;
    }
    final due = last.add(wait);
    // A clock stepped backwards past the last attempt: now, rather than a wait
    // of however far it went.
    return last.isAfter(_now()) ? _now() : due;
  }

  /// Uploads to every server that is owed the board now. Public for tests,
  /// which step the clock rather than waiting.
  @visibleForTesting
  Future<void> runDue() {
    _running = _running.then((_) async {
      final contents = _store.backupContents;
      if (contents == null) return;
      final digest = todoBackupDigest(contents);
      for (final server in _servers) {
        final due = _dueAt(server, digest);
        if (due != null && !due.isAfter(_now())) {
          await _upload(server, contents);
        }
      }
    });
    return _running;
  }

  /// Runs what is owed now, and arms one timer for the earliest server owed
  /// the board later — none when nobody is owed anything.
  void _schedule() {
    if (!_loaded || _disposed) return;
    _timer?.cancel();
    _timer = null;
    final contents = _store.backupContents;
    if (contents == null) return;
    final digest = todoBackupDigest(contents);
    DateTime? next;
    var owedNow = false;
    for (final server in _servers) {
      final due = _dueAt(server, digest);
      if (due == null) continue;
      if (!due.isAfter(_now())) {
        owedNow = true;
      } else if (next == null || due.isBefore(next)) {
        next = due;
      }
    }
    if (!_autoTimers) return;
    if (owedNow) unawaited(runDue().then((_) => _schedule()));
    if (next != null && !owedNow) {
      _timer = Timer(next.difference(_now()), _schedule);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Reads the backup servers and starts sending them the board.
void startTodoRemoteBackup() => unawaited(TodoRemoteBackup.instance.start());
