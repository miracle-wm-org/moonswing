// The todo board's two-way sync with a CalDAV task list.
//
// The board stays where it is — the SQLite database, searched by its own index,
// editable offline, mirrored to the backup file — and the task list is a second
// place the same cards live, which a phone or another desktop can edit. The
// board is always what is on screen; a sync is a conversation with the server
// about what changed since they last agreed, never a reload.
//
// One run, in order:
//
//  1. **Deletes owed.** Cards deleted here since the last run are deleted
//     there, each only if the server's copy is still the one the card was.
//     One the server has changed since is not deleted — it comes back as a
//     card, since an edit is newer than a delete that did not know of it.
//  2. **Pull.** The collection's change token is compared with the one the
//     last run saw; only when it moved is the list read, and only the tasks
//     whose ETag moved are fetched. `planPull` merges them into the board.
//  3. **Push.** Every card that was never sent, or has a field that differs
//     from what the server last had, is written — conditionally, so a task
//     changed on the server since it was read is refused rather than
//     overwritten, and merged on the run that follows.
//
// When it runs: a few seconds after a write of the board that left a card to
// send (so a flurry of edits is one run), when the board is opened, on
// **Sync now**, and on one timer every [kTaskListPoll] while a list is linked
// — so another app's edit arrives within minutes. Nothing at all runs while no
// list is linked: an idle shell with the feature off wakes for it exactly
// never.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/todo/todo_caldav_map.dart';
import 'package:moonswing/todo/todo_database.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// How often a linked list is asked whether anything changed.
const Duration kTaskListPoll = Duration(minutes: 5);

/// How long after a write of the board its changes are sent, so that a burst
/// of edits is one run.
const Duration kTaskListPushDelay = Duration(seconds: 3);

/// How recently a run must have happened for opening the board not to start
/// another.
const Duration kTaskListFreshEnough = Duration(seconds: 30);

/// How many tasks one `calendar-multiget` asks for.
const int _kFetchBatch = 100;

/// The most conflicts kept to show.
const int _kMaxConflicts = 20;

/// The sync, its schedule and how the last run went.
class TodoCalDavSync extends ChangeNotifier {
  TodoCalDavSync._({
    required TodoStore store,
    required CalDavAccountStore accounts,
    DateTime Function()? now,
    bool autoTimers = true,
  }) : _store = store,
       _accounts = accounts,
       _now = now ?? DateTime.now,
       _autoTimers = autoTimers;

  static final TodoCalDavSync instance = TodoCalDavSync._(
    store: TodoStore.instance,
    accounts: CalDavAccountStore.instance,
  );

  /// A sync over [store] and [accounts] that a test drives by hand: no timers,
  /// so call [syncNow].
  @visibleForTesting
  factory TodoCalDavSync.forTesting({
    required TodoStore store,
    required CalDavAccountStore accounts,
    DateTime Function()? now,
  }) => TodoCalDavSync._(
    store: store,
    accounts: accounts,
    now: now,
    autoTimers: false,
  );

  final TodoStore _store;
  final CalDavAccountStore _accounts;
  final DateTime Function() _now;
  final bool _autoTimers;

  Timer? _poll;
  Timer? _push;
  Future<void>? _running;
  bool _again = false;
  bool _started = false;
  DateTime? _lastAttempt;
  DateTime? _lastSuccess;
  String? _error;
  List<String> _conflicts = const [];

  /// The accounts the sync signs in with: the one the linked list is on.
  CalDavAccountStore get accounts => _accounts;

  /// The list the board is linked to, or null.
  TodoRemoteLink? get link => _store.remoteLink;

  /// Whether a run is under way.
  bool get running => _running != null;

  /// When the last run finished cleanly, or null.
  DateTime? get lastSuccess => _lastSuccess;

  /// Why the last run failed, or null. The board keeps working either way;
  /// what did not reach the server goes on the next run that gets through.
  String? get error => _error;

  /// "Title: field, field" for each card both sides changed since the last
  /// run, where the server's value was kept. Shown until dismissed.
  List<String> get conflicts => _conflicts;

  void dismissConflicts() {
    if (_conflicts.isEmpty) return;
    _conflicts = const [];
    notifyListeners();
  }

  /// Hooks the sync to the board and the account, once. What `main()` calls.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _store.onBoardWritten = _onBoardWritten;
    _accounts.addListener(_arm);
    await _accounts.removeLegacyBackupServers();
    await _accounts.load();
    _arm();
    if (link != null && _accounts.signedIn) unawaited(syncNow());
  }

  /// Links the board to [list] and syncs. With [replaceLocal] the board's
  /// synced cards are removed first, so it becomes the list (see
  /// [TodoStore.linkRemote]); otherwise both are merged — every card sent,
  /// every task brought in. Returns where the replaced board was saved, if it
  /// was.
  Future<String?> linkTo(
    CalDavCollection list, {
    bool replaceLocal = false,
  }) async {
    await _running;
    final kept = await _store.linkRemote(
      TodoRemoteLink(
        url: list.url.toString(),
        name: list.name,
        color: list.color,
      ),
      replaceLocal: replaceLocal,
    );
    _error = null;
    _conflicts = const [];
    _lastSuccess = null;
    notifyListeners();
    await syncNow();
    return kept;
  }

  /// Stops syncing. The cards stay on the board, and the tasks on the server.
  Future<void> unlink() async {
    await _running;
    await _store.linkRemote(null);
    _poll?.cancel();
    _poll = null;
    _push?.cancel();
    _push = null;
    _error = null;
    _conflicts = const [];
    _lastSuccess = null;
    notifyListeners();
  }

  /// Runs a sync now — or, when one is under way, once more after it. Answers
  /// [error] as the run left it.
  Future<String?> syncNow() async {
    _push?.cancel();
    _push = null;
    if (_running case final running?) {
      _again = true;
      await running;
      return _error;
    }
    final run = _runRepeating();
    _running = run;
    notifyListeners();
    try {
      await run;
    } finally {
      _running = null;
      _arm();
      notifyListeners();
    }
    return _error;
  }

  /// A sync for the board being opened, unless one ran moments ago. Started
  /// from a microtask, since it is called from the board's `initState` and a
  /// run announces itself to listeners.
  void syncIfStale() {
    if (link == null || !_accounts.signedIn || running) return;
    final last = _lastAttempt;
    if (last != null && _now().difference(last).abs() < kTaskListFreshEnough) {
      return;
    }
    scheduleMicrotask(() => unawaited(syncNow()));
  }

  Future<void> _runRepeating() async {
    // A run whose writes were refused as out of date runs once more at once,
    // to merge what it was refused over; as does one asked for meanwhile.
    for (var pass = 0; pass < 3; pass++) {
      _again = false;
      final conflicted = await _runOnce();
      if (!conflicted && !_again) break;
    }
  }

  /// One run. Answers whether a write was refused as out of date.
  Future<bool> _runOnce() async {
    final link = _store.remoteLink;
    if (link == null) return false;
    _lastAttempt = _now();
    final collection = Uri.parse(link.url);
    final client = _accounts.clientForCollection(collection);
    if (client == null) {
      _error = _accounts.signedIn
          ? 'None of the CalDAV accounts under Settings › Accounts is on '
                '${collection.host}. Sign in to it there to sync with '
                '${link.name}.'
          : 'Not signed in to a CalDAV server. Sign in under Settings › '
                'Accounts to sync with ${link.name}.';
      return false;
    }
    if (!_store.editable) return false;
    String key(String href) => CalDavClient.hrefKey(collection, href);
    var conflicted = false;
    try {
      // 1. Deletes owed.
      final sent = <String>[];
      for (final t in _store.tombstones) {
        try {
          await client.delete(collection.resolve(t.href), etag: t.etag);
        } on CalDavConflict {
          // Changed there since: the pull brings it back.
        }
        sent.add(t.href);
      }
      _store.forgetTombstones(sent);

      // 2. Pull, when anything changed.
      final token = await client.changeToken(collection);
      if (token == null || token != link.changeToken) {
        final listed = await client.listTasks(collection);
        final skip = {for (final t in _store.tombstones) key(t.href)};
        final wanted = hrefsToFetch(_store.items, listed, key, skip: skip);
        final fetched = <CalDavResource>[];
        for (var i = 0; i < wanted.length; i += _kFetchBatch) {
          fetched.addAll(
            await client.fetch(
              collection,
              wanted.sublist(i, (i + _kFetchBatch).clamp(0, wanted.length)),
            ),
          );
        }
        final pull = planPull(
          _store.items,
          listed,
          fetched,
          key,
          now: _now(),
          newId: _store.newCardId,
          skip: skip,
        );
        _store.applyRemotePull(pull);
        if (pull.conflicts.isNotEmpty) {
          final all = [...pull.conflicts, ..._conflicts];
          _conflicts = List.unmodifiable(all.take(_kMaxConflicts));
        }
        // The token read *before* the list: an edit made while it was being
        // read moves the token past this one, and is read next time.
        _store.recordChangeToken(token);
      }

      // 3. Push.
      for (final card in [..._store.items]) {
        if (!needsPush(card)) continue;
        final remote = card.remote;
        final href = remote?.href ?? collection.resolve(taskFileFor(card)).path;
        final ics = writeTask(card, raw: remote?.raw, now: _now());
        try {
          final etag = await client.put(
            collection.resolve(href),
            ics,
            etag: remote?.etag,
            create: remote == null,
          );
          _store.recordRemote(
            card.id,
            TodoRemote(href: href, etag: etag, raw: ics),
          );
        } on CalDavConflict {
          conflicted = true;
        }
      }
      _error = null;
      _lastSuccess = _now();
    } on CalDavException catch (e) {
      _error = e.statusCode == 404
          ? '${link.name} is no longer on the server (404). Link the board '
                'to another task list, or unlink it.'
          : e.message;
    }
    return conflicted;
  }

  /// A write of the board landed: if it left anything to send, send it soon.
  void _onBoardWritten() {
    if (!_autoTimers || link == null || !_accounts.signedIn) return;
    if (_store.tombstones.isEmpty && !_store.items.any(needsPush)) return;
    _push?.cancel();
    _push = Timer(kTaskListPushDelay, () {
      _push = null;
      unawaited(syncNow());
    });
  }

  /// The poll: one timer, and only while a list is linked and signed in to.
  void _arm() {
    final wanted =
        _autoTimers && link != null && _accounts.signedIn && !running;
    _poll?.cancel();
    _poll = wanted ? Timer(kTaskListPoll, () => unawaited(syncNow())) : null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _push?.cancel();
    _accounts.removeListener(_arm);
    if (_store.onBoardWritten == _onBoardWritten) _store.onBoardWritten = null;
    super.dispose();
  }
}

/// Starts the task-list sync. Not a `ShellService`: no panel waits on it, and
/// a server that will not answer is the board's to say.
void startTodoCalDavSync() => unawaited(TodoCalDavSync.instance.start());
