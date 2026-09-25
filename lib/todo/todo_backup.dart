// The todo board's backup file: every card and every note, as JSON, beside
// the database.
//
// The database is the board; this is the copy that survives it. The store
// rewrites it after every write that lands, and reads it back when the
// database is missing or damaged. It is also what a backup server is sent
// (`todo_remote_backup.dart`) and what a restore reads, so there is one format
// for all three.
//
// Written to be kept in Git: pretty-printed, one field per line, cards in board
// order and notes in the order they were made, with no timestamp of its own —
// so a file whose board has not changed is byte-for-byte the file it was, and a
// commit of it is a diff of what the user changed.
//
// Flutter-free, for `test/todo_backup_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:moonswing/todo/todo_model.dart';

/// The value of the file's `format` key, which is what tells a backup from any
/// other JSON a user might point a restore at.
const String kTodoBackupFormat = 'moonswing-todo-backup';

/// The backup format's version. Checked only to refuse a *newer* file.
const int kTodoBackupVersion = 1;

/// The file's name, in [todoBackupDirectory].
const String kTodoBackupFileName = 'todo-backup.json';

/// The backup's directory under the board's own: a directory of its own, so
/// that `git init` there tracks the backup and nothing else — never the
/// database, which is binary and rewritten on every drag.
String todoBackupDirectory(String boardDirectory) => '$boardDirectory/backup';

/// A whole board, as a backup holds it.
class TodoBackup {
  const TodoBackup({required this.items, required this.notes});

  /// In board order.
  final List<TodoItem> items;
  final List<NoteItem> notes;

  bool get isEmpty => items.isEmpty && notes.isEmpty;

  /// "12 cards and 3 notes".
  String get summary {
    String count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
    return '${count(items.length, 'card')} and ${count(notes.length, 'note')}';
  }
}

/// The backup file's contents for [items] (in board order) and [notes] (in any
/// order: they are written oldest first, so editing a note moves no line but
/// its own).
String encodeTodoBackup(List<TodoItem> items, List<NoteItem> notes) {
  final sortedNotes = [...notes]
    ..sort((a, b) {
      final byCreated = a.created.compareTo(b.created);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  return '${const JsonEncoder.withIndent('  ').convert({
    'format': kTodoBackupFormat,
    'version': kTodoBackupVersion,
    'items': [for (final item in items) item.toJson()],
    'notes': [for (final note in sortedNotes) note.toJson()],
  })}\n';
}

/// The board in [source].
///
/// Also reads an old `todo.json`, which is the same shape without the notes,
/// so a board saved by a shell from before the database can be restored the
/// same way. A row that cannot be a card or a note costs that row, and a
/// duplicate id the later copy; only a file that is not a board at all — or one
/// from a newer shell — throws.
TodoBackup decodeTodoBackup(String source) {
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (e) {
    throw TodoFormatException('The backup is not valid JSON: ${e.message}');
  }
  if (json is! Map) {
    throw const TodoFormatException('The backup does not hold a board.');
  }
  final format = json['format'];
  if (format == null) {
    // No format key: an old todo.json, whose own reader has its own rules.
    return TodoBackup(items: decodeTodoFile(source), notes: const []);
  }
  if (format != kTodoBackupFormat) {
    throw const TodoFormatException('The backup does not hold a board.');
  }
  final version = json['version'];
  if (version is int && version > kTodoBackupVersion) {
    throw TodoFormatException(
      'The backup was written by a newer version of the shell (format '
      '$version).',
    );
  }
  final seen = <String>{};
  return TodoBackup(
    items: [
      if (json['items'] case final List<Object?> rows)
        for (final row in rows)
          if (TodoItem.fromJson(row) case final item? when seen.add(item.id))
            item,
    ],
    notes: [
      if (json['notes'] case final List<Object?> rows)
        for (final row in rows)
          if (NoteItem.fromJson(row) case final note? when seen.add(note.id))
            note,
    ],
  );
}

/// The backup file on disk: written atomically, and only when what it holds
/// changes.
class TodoBackupFile {
  TodoBackupFile(this.path);

  /// Where the backup is, as the user is told it.
  final String path;

  /// What the file was last known to hold, so an unchanged board is not a
  /// write — a rewrite of identical bytes would still touch the modification
  /// time, and with it every tool watching the file.
  String? _known;

  /// The file actually written: [path], or wherever it links to. A user who
  /// keeps the backup in a dotfiles repository may well replace it with a
  /// symlink, and a rename over the link would quietly replace the link with a
  /// file and stop the repository seeing anything again.
  String _target() {
    try {
      if (FileSystemEntity.isLinkSync(path)) {
        return File(path).resolveSymbolicLinksSync();
      }
    } catch (_) {
      // A dangling link: written through as a new file where it points.
      try {
        return Link(path).targetSync();
      } catch (_) {}
    }
    return path;
  }

  /// Writes [contents], unless the file already holds exactly that. Returns
  /// whether anything was written; throws [FileSystemException] when the write
  /// fails, leaving the previous file whole.
  ///
  /// Through a temporary file beside it and a rename, so a crash or a full
  /// disk mid-write leaves the last backup rather than half of this one.
  Future<bool> write(String contents) async {
    final target = _target();
    final file = File(target);
    if (_known == null) {
      try {
        if (await file.exists()) _known = await file.readAsString();
      } catch (_) {
        // Unreadable: written over, which is what makes it readable again.
      }
    }
    if (_known == contents) return false;
    await file.parent.create(recursive: true);
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final temporary = File('$dir/.$name.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      rethrow;
    }
    _known = contents;
    return true;
  }

  /// The backup, or null when there is no file. Throws [TodoFormatException]
  /// for a file that is there and is not a board.
  Future<({TodoBackup backup, DateTime saved})?> read() async {
    final file = File(_target());
    if (!await file.exists()) return null;
    final String source;
    try {
      source = await file.readAsString();
    } on FileSystemException catch (e) {
      throw TodoFormatException('Could not read $path: ${e.message}');
    }
    return (backup: decodeTodoBackup(source), saved: await file.lastModified());
  }

  /// When the file was last written, or null when there is none.
  Future<DateTime?> lastModified() async {
    try {
      final file = File(_target());
      return await file.exists() ? await file.lastModified() : null;
    } catch (_) {
      return null;
    }
  }
}

/// A 64-bit FNV-1a digest of [text]'s UTF-8, as hex: how a backup server's
/// record says what it was last sent, across restarts, without keeping the
/// board itself in the record.
String todoBackupDigest(String text) {
  // The shell only runs on the VM, whose `int` is 64-bit and wraps on
  // overflow — which is exactly FNV's arithmetic mod 2^64.
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  String half(int value) => value.toRadixString(16).padLeft(8, '0');
  return '${half(hash >>> 32)}${half(hash & 0xffffffff)}';
}
