// The clipboard history, for the whole shell: one watcher however many bars
// carry the button.
//
// The singleton-`ChangeNotifier`-with-leases shape. The leases are what make the
// history cost nothing on a shell that does not use it: every clipboard button
// on every bar takes one for as long as it is on screen, and the panel takes
// one while it is open, so the watcher runs exactly while some surface could
// show what it records — and a shell with no `"clipboard"` in any layout never
// forks `wl-paste` at all.
//
// What it keeps lives in `$XDG_STATE_HOME/moonswing/clipboard` (0700): an index,
// `history.json`, holding every entry and the text of the text ones, and one
// file per picture or media entry, named by the entry's id. With
// `persist = false` the directory is wiped when the history first loads, and
// the index is never written.
//
// Flutter-free apart from `ChangeNotifier`, so the whole of it is a unit test.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/wl_clipboard.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart'
    show ClipboardResult, kClipboardCommand, kClipboardPackage;
import 'package:moonswing/native/libc.dart';

/// The most text one entry keeps, whatever `max_item_mb` says: text lives in
/// the index, which is rewritten on every change and read whole at start-up.
const int kMaxClipboardTextBytes = 2 * 1024 * 1024;

/// How long the "Copied" mark stays on the entry just put back.
const Duration kClipboardCopiedFlash = Duration(milliseconds: 1600);

class ClipboardHistoryStore extends ChangeNotifier {
  ClipboardHistoryStore._({
    ClipboardBackend? backend,
    String? directory,
    DateTime Function()? clock,
  }) : _backend = backend ?? const WlClipboardBackend(),
       _directory = directory,
       _clock = clock ?? DateTime.now;

  static final ClipboardHistoryStore instance = ClipboardHistoryStore._();

  /// A detached store over an injected backend and directory, so a test can
  /// take real leases without forking anything or touching the user's history.
  @visibleForTesting
  factory ClipboardHistoryStore.forTesting({
    required ClipboardBackend backend,
    required String directory,
    DateTime Function()? clock,
  }) => ClipboardHistoryStore._(
    backend: backend,
    directory: directory,
    clock: clock,
  );

  final ClipboardBackend _backend;
  final String? _directory;
  final DateTime Function() _clock;

  /// Where the history lives. Resolved per call, `GithubTokenStore`'s rule, so
  /// a test that sets `XDG_STATE_HOME` cannot be defeated by a cached value.
  String get directory => _directory ?? _defaultDirectory();

  static String _defaultDirectory() {
    final env = Platform.environment;
    final state = env['XDG_STATE_HOME'];
    if (state != null && state.isNotEmpty) return '$state/moonswing/clipboard';
    final home = env['HOME'] ?? '.';
    return '$home/.local/state/moonswing/clipboard';
  }

  String get _indexPath => '$directory/history.json';

  // --- configuration -------------------------------------------------------

  ClipboardConfig _config = const ClipboardConfig();

  /// `[modules.clipboard]`, pushed in by the module's `fromMap`. The root reads
  /// the side and width from here when it creates the panel.
  ClipboardConfig get config => _config;

  /// Takes a new `[modules.clipboard]`.
  ///
  /// Runs inside `AppConfig.fromMap` — every settings keystroke — so it never
  /// notifies synchronously: a trim that removes entries is announced on the
  /// next microtask.
  void configure(ClipboardConfig config) {
    if (config == _config) return;
    final persistTurnedOff = _config.persist && !config.persist;
    final persistTurnedOn = !_config.persist && config.persist;
    _config = config;
    if (!_loaded) return;
    if (persistTurnedOff) {
      // Turning persistence off is a request that the history stop being on
      // disk, so the index goes now rather than at the next start.
      _saveTimer?.cancel();
      unawaited(_deleteFile(_indexPath));
    }
    final trimmed = _trim();
    if (trimmed || persistTurnedOn) _scheduleSave();
    if (trimmed) scheduleMicrotask(_notify);
  }

  // --- published state -----------------------------------------------------

  final List<ClipboardEntry> _entries = [];

  /// Newest first.
  List<ClipboardEntry> get entries => List.unmodifiable(_entries);

  bool _loaded = false;

  /// Whether the saved history has been read. The panel shows a loader until
  /// then rather than an empty list it would have to take back.
  bool get loaded => _loaded;

  ClipboardWatchFailure? _failure;

  /// Why the history is not being kept, or null while it is.
  String? get error => _failure?.message;

  /// Whether [error] is the missing `wl-paste`, which the panel names the
  /// package for.
  bool get toolMissing => _failure?.missing ?? false;

  /// Whether [error] is a compositor without data-control.
  bool get unsupported => _failure?.unsupported ?? false;

  String? _copyError;

  /// Why the last click on an entry did not put it back, or null.
  String? get copyError => _copyError;

  final ValueNotifier<String?> _justCopied = ValueNotifier(null);

  /// The id of the entry put back on the clipboard a moment ago, for its
  /// "Copied" mark; null otherwise. Its own listenable, so the mark appearing
  /// and going rebuilds the one card that shows it.
  ValueListenable<String?> get justCopied => _justCopied;
  Timer? _justCopiedTimer;

  /// The file a picture or media entry's payload is kept in.
  String? payloadPath(ClipboardEntry entry) =>
      entry.kind.storesFile ? '$directory/${entry.id}' : null;

  // --- leasing -------------------------------------------------------------

  int _leases = 0;
  StreamSubscription<ClipboardChange>? _watch;
  Future<void>? _loading;
  bool _disposed = false;

  @visibleForTesting
  int get leaseCount => _leases;

  /// Whether the watcher is running.
  @visibleForTesting
  bool get watching => _watch != null;

  /// Take a lease. The first one loads the history and starts the watcher.
  ///
  /// Nothing is notified synchronously — this runs inside the acquirer's
  /// `initState`.
  void acquire() {
    _leases++;
    if (_leases == 1) unawaited(_start());
  }

  /// Give one back. The last one stops the watcher; the history stays.
  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases == 0) _stop();
  }

  /// Starts the watcher again after a failure. What the panel's Retry calls.
  void retry() {
    _failure = null;
    _stop();
    _notify();
    if (_leases > 0) unawaited(_start());
  }

  Future<void> _start() async {
    await (_loading ??= _load());
    if (_leases == 0 || _watch != null || _disposed) return;
    _watch = _backend.watch().listen(
      _onChange,
      onError: (Object error) {
        _watch = null;
        _failure = error is ClipboardWatchFailure
            ? error
            : ClipboardWatchFailure('The clipboard watcher failed: $error');
        _notify();
      },
      onDone: () => _watch = null,
      cancelOnError: true,
    );
    // The load may have brought entries in; this is the first anybody hears
    // of them, and it is safely after `initState`.
    _notify();
  }

  void _stop() {
    unawaited(_watch?.cancel());
    _watch = null;
  }

  // --- capture -------------------------------------------------------------

  bool _capturing = false;
  bool _capturePending = false;

  void _onChange(ClipboardChange change) {
    // A cleared selection leaves the history as it was — the point of a
    // history is that what was copied is still here after it is gone — and a
    // password manager's copy is never read at all.
    if (change != ClipboardChange.data) return;
    _capturePending = true;
    if (!_capturing) unawaited(_drainCaptures());
  }

  /// One capture at a time, and the newest change wins: a burst of copies
  /// while a big picture is being read collapses into one more read.
  Future<void> _drainCaptures() async {
    _capturing = true;
    try {
      while (_capturePending && !_disposed) {
        _capturePending = false;
        await _capture();
      }
    } finally {
      _capturing = false;
    }
  }

  Future<void> _capture() async {
    final types = await _backend.listTypes();
    if (types == null) return;
    final choice = pickClipboardType(types);
    if (choice == null) return;

    var kind = choice.kind;
    final limit = kind.storesFile
        ? _config.maxItemBytes
        : (_config.maxItemBytes < kMaxClipboardTextBytes
              ? _config.maxItemBytes
              : kMaxClipboardTextBytes);
    final bytes = await _backend.read(choice.mime, maxBytes: limit);
    if (bytes == null || bytes.isEmpty || _disposed) return;

    var mime = choice.mime;
    String? text;
    Uint8List payload = bytes;
    switch (kind) {
      case ClipboardKind.text:
        text = utf8.decode(bytes, allowMalformed: true);
        if (text.trim().isEmpty) return;
        // Plain text is put back as plain text however it was offered; a
        // `text/html` alone keeps its type, or it would paste as markup.
        if (!mime.toLowerCase().startsWith('text/') ||
            mime.toLowerCase().startsWith('text/plain')) {
          mime = kClipboardTextMime;
        }
        payload = utf8.encode(text);
      case ClipboardKind.files:
        final raw = utf8.decode(bytes, allowMalformed: true);
        final paths = parseFileUris(raw);
        if (paths.isEmpty) {
          // Web links in a uri-list: text the user can paste anywhere.
          kind = ClipboardKind.text;
          text = raw.trim();
          if (text.isEmpty) return;
          mime = kClipboardTextMime;
        } else {
          text = fileUriList(paths);
          mime = 'text/uri-list';
        }
        payload = utf8.encode(text);
      case ClipboardKind.image:
      case ClipboardKind.media:
      case ClipboardKind.binary:
        break;
    }

    final hash = await _digest(kind, payload);
    if (_disposed) return;
    await _record(kind: kind, mime: mime, hash: hash, text: text, bytes: bytes);
  }

  /// A digest of [kind] and [bytes]. Off the UI isolate past a size where
  /// hashing would cost a frame.
  static Future<String> _digest(ClipboardKind kind, Uint8List bytes) async {
    String compute() => '${kind.name}:${sha1.convert(bytes)}';
    if (bytes.length < 256 * 1024) return compute();
    return Isolate.run(compute);
  }

  int _idCounter = 0;

  String _newId(DateTime now) =>
      '${now.microsecondsSinceEpoch}-${_idCounter++}';

  Future<void> _record({
    required ClipboardKind kind,
    required String mime,
    required String hash,
    required String? text,
    required Uint8List bytes,
  }) async {
    final now = _clock();
    // Already in the history — a copy of the same thing again, or an entry
    // the user just put back from this panel — so it moves to the top rather
    // than appearing twice.
    final existing = _entries.indexWhere((e) => e.hash == hash);
    // Already on top: the watcher reporting what is already the newest entry
    // — the selection as it stood when the watcher started, or the shell's own
    // copy from this panel coming back. Nothing moved, so nothing is written.
    if (existing == 0) return;
    if (existing > 0) {
      final moved = _entries.removeAt(existing).copyWith(copiedAt: now);
      _entries.insert(0, moved);
    } else {
      final id = _newId(now);
      if (kind.storesFile && !await _writePayload(id, bytes)) return;
      if (_disposed) return;
      _entries.insert(
        0,
        ClipboardEntry(
          id: id,
          kind: kind,
          mime: mime,
          copiedAt: now,
          size: bytes.length,
          hash: hash,
          text: text,
        ),
      );
      _trim();
    }
    _scheduleSave();
    _notify();
  }

  /// Drops the oldest unpinned entries past `max_entries`. Whether any went.
  bool _trim() {
    var unpinned = _entries.where((e) => !e.pinned).length;
    var removed = false;
    for (
      var i = _entries.length - 1;
      i >= 0 && unpinned > _config.maxEntries;
      i--
    ) {
      final entry = _entries[i];
      if (entry.pinned) continue;
      _entries.removeAt(i);
      _deletePayload(entry);
      unpinned--;
      removed = true;
    }
    return removed;
  }

  // --- what the panel does -------------------------------------------------

  /// Puts [entry] back on the clipboard, and moves it to the top.
  Future<ClipboardResult> copy(ClipboardEntry entry) async {
    final Stream<List<int>> data;
    final String mime;
    switch (entry.kind) {
      case ClipboardKind.text:
        mime = entry.mime;
        data = Stream.value(utf8.encode(entry.text ?? ''));
      case ClipboardKind.files:
        // Always offered as a uri-list, whatever it was read as: GNOME's
        // private type is understood by its own file manager alone.
        mime = 'text/uri-list';
        data = Stream.value(utf8.encode(fileUriList(entry.paths)));
      case ClipboardKind.image:
      case ClipboardKind.media:
      case ClipboardKind.binary:
        mime = entry.mime;
        final file = File(payloadPath(entry)!);
        if (!await file.exists()) {
          _copyError = 'That entry\'s file is gone, so it cannot be copied.';
          _notify();
          return ClipboardResult.failed;
        }
        data = file.openRead();
    }

    final result = await _backend.write(mime, data);
    if (_disposed) return result;
    switch (result) {
      case ClipboardResult.copied:
        _copyError = null;
        final index = _entries.indexWhere((e) => e.id == entry.id);
        if (index >= 0) {
          final moved = _entries.removeAt(index).copyWith(copiedAt: _clock());
          _entries.insert(0, moved);
          _scheduleSave();
        }
        _flashCopied(entry.id);
      case ClipboardResult.unavailable:
        _copyError =
            'Copying needs $kClipboardCommand, from the $kClipboardPackage '
            'package.';
      case ClipboardResult.failed:
        _copyError = '$kClipboardCommand refused to take the clipboard.';
    }
    _notify();
    return result;
  }

  void _flashCopied(String id) {
    _justCopied.value = id;
    _justCopiedTimer?.cancel();
    _justCopiedTimer = Timer(kClipboardCopiedFlash, () {
      if (!_disposed) _justCopied.value = null;
    });
  }

  /// Forgets [entry].
  void remove(ClipboardEntry entry) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return;
    _deletePayload(_entries.removeAt(index));
    _scheduleSave();
    _notify();
  }

  /// Forgets everything that is not pinned.
  void clear() {
    final gone = _entries.where((e) => !e.pinned).toList();
    if (gone.isEmpty) return;
    _entries.removeWhere((e) => !e.pinned);
    gone.forEach(_deletePayload);
    _scheduleSave();
    _notify();
  }

  /// Pins [entry], or unpins it.
  void togglePin(ClipboardEntry entry) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return;
    _entries[index] = _entries[index].copyWith(pinned: !_entries[index].pinned);
    // Unpinning can put the history back over its limit.
    _trim();
    _scheduleSave();
    _notify();
  }

  /// Clears [copyError] — the panel's dismiss on that banner.
  void dismissCopyError() {
    if (_copyError == null) return;
    _copyError = null;
    _notify();
  }

  // --- disk ----------------------------------------------------------------

  Future<void> _load() async {
    try {
      final dir = Directory(directory);
      if (!_config.persist) {
        // Whatever an earlier session left — this one's pictures included,
        // if the shell restarted — is not this session's history.
        if (await dir.exists()) await dir.delete(recursive: true);
      } else {
        final index = File(_indexPath);
        if (await index.exists()) {
          final decoded = jsonDecode(await index.readAsString());
          final rows = decoded is Map ? decoded['entries'] : null;
          final seen = <String>{};
          for (final row in rows is List ? rows : const []) {
            final entry = ClipboardEntry.fromJson(row);
            // A bad row, a duplicate id, or a picture whose file has gone
            // costs that entry and nothing else.
            if (entry == null || !seen.add(entry.id)) continue;
            if (entry.kind.storesFile &&
                !await File(payloadPath(entry)!).exists()) {
              continue;
            }
            _entries.add(entry);
          }
        }
        await _sweepOrphans();
      }
    } catch (error) {
      debugPrint('clipboard: reading the history failed: $error');
    }
    _trim();
    _loaded = true;
  }

  /// Deletes payload files no entry names — left by a crash between writing a
  /// picture and saving the index, or by a hand-edited index.
  Future<void> _sweepOrphans() async {
    final dir = Directory(directory);
    if (!await dir.exists()) return;
    final wanted = {for (final e in _entries) e.id};
    await for (final item in dir.list()) {
      final name = item.path.substring(item.path.lastIndexOf('/') + 1);
      if (name == 'history.json' || name.startsWith('history.json.')) continue;
      if (item is File && !wanted.contains(name)) {
        await _deleteFile(item.path);
      }
    }
  }

  Future<void> _ensureDirectory() async {
    final dir = Directory(directory);
    if (await dir.exists()) return;
    await dir.create(recursive: true);
    // Narrowed before anything is written into it: what people copy includes
    // what they would not want another user on the machine to read.
    chmodPath(directory, 0x1C0); // 0700
  }

  Future<bool> _writePayload(String id, Uint8List bytes) async {
    try {
      await _ensureDirectory();
      final path = '$directory/$id';
      await File(path).writeAsBytes(bytes, flush: true);
      chmodPath(path, 0x180); // 0600
      return true;
    } catch (error) {
      debugPrint('clipboard: keeping a copied picture failed: $error');
      return false;
    }
  }

  void _deletePayload(ClipboardEntry entry) {
    final path = payloadPath(entry);
    if (path != null) unawaited(_deleteFile(path));
  }

  static Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to surface: the entry is already gone from the history.
    }
  }

  Timer? _saveTimer;

  /// Debounced, so a burst of copies is one write.
  void _scheduleSave() {
    if (!_config.persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    if (!_config.persist || _disposed) return;
    try {
      await _ensureDirectory();
      final body = jsonEncode({
        'version': 1,
        'entries': [for (final e in _entries) e.toJson()],
      });
      // Atomic: a crash mid-write leaves the previous index, not half of one.
      final tmp = File('$_indexPath.tmp');
      await tmp.writeAsString(body, flush: true);
      chmodPath(tmp.path, 0x180); // 0600
      await tmp.rename(_indexPath);
    } catch (error) {
      debugPrint('clipboard: saving the history failed: $error');
    }
  }

  /// Writes any pending save now. For tests.
  @visibleForTesting
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _save();
    }
  }

  /// Waits for the first load. For tests.
  @visibleForTesting
  Future<void> get ready => _loading ??= _load();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    _saveTimer?.cancel();
    _justCopiedTimer?.cancel();
    _justCopied.dispose();
    super.dispose();
  }
}
