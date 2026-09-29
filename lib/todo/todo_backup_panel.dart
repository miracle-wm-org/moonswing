// The todo board's backup and sync: where the backup file is, how to keep it
// somewhere safer, restoring from it — and the CalDAV task list the board is
// kept in step with.
//
// It owns no state of its own worth keeping. [TodoStore] writes the file and
// restores from it, and [TodoCalDavSync] owns the link and its runs; this is
// the card over the board that shows both.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart' show openUriWithDefault;
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_caldav_sync.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The backups card's width.
const double kTodoBackupPanelWidth = 640;

/// [path] with the home directory written `~`, as the user would type it.
String displayPath(String path, {String? home}) {
  final h = home ?? Platform.environment['HOME'];
  if (h == null || h.isEmpty || h == '/') return path;
  if (path == h) return '~';
  if (path.startsWith('$h/')) return '~${path.substring(h.length)}';
  return path;
}

/// "just now", "5 minutes ago", "3 hours ago", or a date and time.
String describeBackupMoment(DateTime at, DateTime now) {
  final ago = now.difference(at);
  if (ago.isNegative || ago < const Duration(minutes: 1)) return 'just now';
  if (ago < const Duration(hours: 1)) {
    final m = ago.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (ago < const Duration(hours: 24)) {
    final h = ago.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  final local = at.toLocal();
  return 'on ${formatDate(local)} at ${two(local.hour)}:${two(local.minute)}';
}

/// The one line under the board that says where its backup is — the part of
/// this feature that has to be seen without being looked for. A click opens
/// the backups card.
class TodoBackupFooter extends StatelessWidget {
  const TodoBackupFooter({
    super.key,
    required this.store,
    required this.sync,
    required this.onOpen,
  });

  final TodoStore store;
  final TodoCalDavSync sync;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, sync]),
      builder: (context, _) {
        final error = store.backupError;
        final link = sync.link;
        final failing = link != null && sync.error != null;
        final text = StringBuffer(
          error != null
              ? 'The backup file could not be written'
              : 'Backed up to ${displayPath(store.backupPath)}',
        );
        if (link != null) {
          text.write(
            failing
                ? ' · ${link.name} could not be synced'
                : ' · synced with ${link.name}',
          );
        }
        final warn = error != null || failing;
        return HoverRegion(
          onTap: onOpen,
          builder: (context, hovered) => Container(
            constraints: const BoxConstraints(
              minHeight: ShellSizes.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            child: Row(
              children: [
                FaIcon(
                  warn
                      ? FontAwesomeIcons.triangleExclamation
                      : FontAwesomeIcons.floppyDisk,
                  size: ShellFontSizes.caption,
                  color: warn
                      ? kErrorColor
                      : theme.popupForeground.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.secondary,
                      color: warn
                          ? kErrorColor
                          : theme.popupForeground.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Backups…',
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.accentText,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The backups card, over a scrim that covers the board.
class TodoBackupLayer extends StatelessWidget {
  const TodoBackupLayer({
    super.key,
    required this.store,
    required this.sync,
    required this.onDone,
    required this.onOpenAccounts,
    this.copy = copyTextToClipboard,
    this.openFolder = _openFolder,
  });

  final TodoStore store;
  final TodoCalDavSync sync;
  final VoidCallback onDone;

  /// Opens Settings › Accounts, where a CalDAV server is signed in to.
  final VoidCallback onOpenAccounts;

  /// How "Copy path" copies; a test records instead of forking `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  /// How "Open folder" opens; a test records instead of launching one.
  final bool Function(String directory) openFolder;

  static bool _openFolder(String directory) =>
      openUriWithDefault(Uri.directory(directory).toString());

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return GestureDetector(
      // Absorbs clicks meant for the board underneath; not a dismiss, which is
      // Done's alone.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: theme.scrim,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kTodoBackupPanelWidth.clamp(
                  0,
                  (constraints.maxWidth - 32).clamp(0, double.infinity),
                ),
                maxHeight: (constraints.maxHeight - 32).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: _BackupCard(
                store: store,
                sync: sync,
                onDone: onDone,
                onOpenAccounts: onOpenAccounts,
                copy: copy,
                openFolder: openFolder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupCard extends StatefulWidget {
  const _BackupCard({
    required this.store,
    required this.sync,
    required this.onDone,
    required this.onOpenAccounts,
    required this.copy,
    required this.openFolder,
  });

  final TodoStore store;
  final TodoCalDavSync sync;
  final VoidCallback onDone;
  final VoidCallback onOpenAccounts;
  final Future<ClipboardResult> Function(String text) copy;
  final bool Function(String directory) openFolder;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  /// The outcome of the last thing the user asked for — a copy, a restore —
  /// said where they asked for it.
  String? _message;
  bool _messageIsError = false;
  bool _restoring = false;

  /// The task list picked to link to, and whether linking replaces the board.
  CalDavCollection? _chosen;
  bool _replaceBoard = false;
  bool _linking = false;

  late final Listenable _all = Listenable.merge([
    widget.store,
    widget.sync,
    widget.sync.accounts,
  ]);

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _copyPath() async {
    final result = await widget.copy(widget.store.backupPath);
    _say(switch (result) {
      ClipboardResult.copied => 'The path is on the clipboard.',
      ClipboardResult.unavailable =>
        'Install $kClipboardPackage to copy it, or select it above.',
      ClipboardResult.failed => '$kClipboardCommand could not copy it.',
    }, error: result != ClipboardResult.copied);
  }

  void _openFolder() {
    final dir = File(widget.store.backupPath).parent.path;
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {}
    if (!widget.openFolder(dir)) {
      _say('Could not open $dir.', error: true);
    }
  }

  /// Replaces the board with [backup] once the user has said yes.
  Future<void> _restore(
    Future<TodoBackup> Function() fetch, {
    required String from,
  }) async {
    setState(() => _restoring = true);
    final TodoBackup backup;
    try {
      backup = await fetch();
    } catch (e) {
      setState(() => _restoring = false);
      _say(e.toString(), error: true);
      return;
    }
    if (!mounted) return;
    final store = widget.store;
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Replace the board?',
      message:
          'The backup $from holds ${backup.summary}. It will replace '
          'everything on the board now (${store.items.length} cards and '
          '${store.notes.length} notes).',
      warning:
          store.editable && (store.items.isNotEmpty || store.notes.isNotEmpty)
          ? 'The board as it is now is saved beside the backup file first, so '
                'this can be undone by restoring that.'
          : null,
      confirmLabel: 'Replace',
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _restoring = false);
      return;
    }
    try {
      final kept = await store.restore(backup);
      _say(
        'Restored ${backup.summary}.'
        '${kept == null ? '' : ' The board it replaced was saved as ${displayPath(kept)}.'}',
      );
    } on TodoFormatException catch (e) {
      _say(e.message, error: true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _restoreFromFile() => _restore(() async {
    final saved = await widget.store.readBackupFile();
    if (saved == null) {
      throw TodoFormatException(
        'There is no backup file at ${widget.store.backupPath}.',
      );
    }
    return saved.backup;
  }, from: 'file');

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.accent),
        boxShadow: [BoxShadow(color: theme.popupShadowColor, blurRadius: 24)],
      ),
      child: ListenableBuilder(
        listenable: _all,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Backups',
                      style: TextStyle(
                        fontSize: ShellFontSizes.title,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: SettingsActionButton(
                      label: 'Done',
                      primary: true,
                      onTap: widget.onDone,
                    ),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: _messageIsError ? kErrorColor : theme.accentText,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ..._buildFileSection(theme),
              const SizedBox(height: 22),
              ..._buildSyncSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _link(CalDavCollection list) async {
    if (_replaceBoard) {
      final confirmed = await showSettingsConfirm(
        context,
        title: 'Replace the board with ${list.name}?',
        message:
            'Every card on the board is removed — except meetings from the '
            'calendar, which are never synced — and the tasks on '
            '${list.name} take their place.',
        warning:
            'The board as it is now is saved beside the backup file first, so '
            'this can be undone by restoring that.',
        confirmLabel: 'Replace',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _linking = true);
    try {
      final kept = await widget.sync.linkTo(list, replaceLocal: _replaceBoard);
      final error = widget.sync.error;
      _say(
        error ??
            'Linked to ${list.name}.'
                '${kept == null ? '' : ' The board it replaced was saved as ${displayPath(kept)}.'}',
        error: error != null,
      );
    } on TodoFormatException catch (e) {
      _say(e.message, error: true);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    final link = widget.sync.link;
    if (link == null) return;
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Stop syncing with ${link.name}?',
      message:
          'The cards stay on the board and the tasks stay on the server; '
          'they simply stop following each other.',
      confirmLabel: 'Unlink',
    );
    if (confirmed) await widget.sync.unlink();
  }

  List<Widget> _buildSyncSection(ThemeConfig theme) {
    final sync = widget.sync;
    final accounts = sync.accounts;
    final link = sync.link;
    final muted = theme.popupForeground.withValues(alpha: 0.7);
    final intro = Text(
      'Keep the board in step with a task list on a CalDAV server, so a phone '
      'or another computer can read and change the same cards. Meetings from '
      'the calendar stay on this board only.',
      style: TextStyle(fontSize: ShellFontSizes.secondary, color: muted),
    );
    if (link != null) {
      final error = sync.error;
      final success = sync.lastSuccess;
      final status = sync.running
          ? 'Syncing…'
          : error ??
                (success == null
                    ? 'Not synced yet.'
                    : 'Last synced ${describeBackupMoment(success, widget.store.now)}.');
      return [
        const _Heading('Task list'),
        intro,
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.popupBackground,
            borderRadius: BorderRadius.circular(ShellRadii.control),
            border: Border.all(
              color: error != null
                  ? kErrorColor.withValues(alpha: 0.5)
                  : theme.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.listCheck,
                    size: ShellFontSizes.caption,
                    color: _parseColor(link.color) ?? theme.accentText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      link.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                link.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: theme.popupForeground.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: error != null && !sync.running
                      ? kErrorColor
                      : theme.popupForeground.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SettingsActionButton(
                    label: 'Sync now',
                    compact: true,
                    loading: sync.running,
                    onTap: () => sync.syncNow(),
                  ),
                  if (accounts.account == null)
                    SettingsActionButton(
                      label: 'Sign in…',
                      compact: true,
                      onTap: widget.onOpenAccounts,
                    ),
                  SettingsActionButton(
                    label: 'Unlink',
                    compact: true,
                    enabled: !sync.running,
                    onTap: _unlink,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (sync.conflicts.isNotEmpty) ...[
          const SizedBox(height: 10),
          SettingsBanner(
            title: 'Changed in both places',
            message:
                'These cards were changed here and on the server at once. '
                "The server's version of each field was kept:\n"
                '${sync.conflicts.map((c) => '• $c').join('\n')}',
            action: SettingsActionButton(
              label: 'Dismiss',
              compact: true,
              onTap: sync.dismissConflicts,
            ),
          ),
        ],
      ];
    }
    final account = accounts.account;
    if (account == null) {
      return [
        const _Heading('Task list'),
        intro,
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: SettingsHint('No CalDAV server is signed in to.'),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Set up in Settings…',
              compact: true,
              onTap: widget.onOpenAccounts,
            ),
          ],
        ),
      ];
    }
    final lists = accounts.taskLists;
    final chosen = lists.contains(_chosen)
        ? _chosen
        : (lists.isEmpty ? null : lists.first);
    return [
      const _Heading('Task list'),
      intro,
      const SizedBox(height: 10),
      if (accounts.error.isNotEmpty) ...[
        Text(
          accounts.error,
          style: const TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: kErrorColor,
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (lists.isEmpty)
        Row(
          children: [
            Expanded(
              child: SettingsHint('No task lists found on ${account.label}.'),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Look again',
              compact: true,
              loading: accounts.busy,
              onTap: accounts.refreshTaskLists,
            ),
          ],
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: SettingsDropdown<CalDavCollection>(
                items: [
                  for (final l in lists)
                    SettingsDropdownItem(value: l, label: l.name),
                ],
                selected: chosen,
                onSelected: (l) => setState(() => _chosen = l),
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Link',
              primary: true,
              compact: true,
              loading: _linking,
              enabled: chosen != null && !_linking,
              onTap: () => _link(chosen!),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _replaceBoard
                    ? 'Replace the board with the list: its cards are removed '
                          'and the tasks take their place.'
                    : 'Merge: every card goes to the list, and every task on '
                          'it comes to the board.',
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SettingsToggle(
              value: _replaceBoard,
              onChanged: (v) => setState(() => _replaceBoard = v),
            ),
          ],
        ),
      ],
    ];
  }

  static Color? _parseColor(String? hex) {
    final match = RegExp(r'^#([0-9a-f]{6})$').firstMatch(hex ?? '');
    if (match == null) return null;
    return Color(0xFF000000 | int.parse(match[1]!, radix: 16));
  }

  List<Widget> _buildFileSection(ThemeConfig theme) {
    final store = widget.store;
    final saved = store.backupSaved;
    final error = store.backupError;
    final dir = displayPath(File(store.backupPath).parent.path);
    final muted = theme.popupForeground.withValues(alpha: 0.7);
    return [
      const _Heading('Backup file'),
      Text(
        'Every change to the board is also saved to this file. If the '
        'database is ever damaged or missing, the board is rebuilt from it '
        'when the shell starts.',
        style: TextStyle(fontSize: ShellFontSizes.secondary, color: muted),
      ),
      const SizedBox(height: 10),
      _CodeBox(text: displayPath(store.backupPath)),
      const SizedBox(height: 6),
      Text(
        error ??
            (saved == null
                ? 'Not written yet — it is written as soon as the board is.'
                : 'Last written ${describeBackupMoment(saved, store.now)}.'),
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          color: error != null ? kErrorColor : muted,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SettingsActionButton(
            label: 'Copy path',
            compact: true,
            onTap: _copyPath,
          ),
          SettingsActionButton(
            label: 'Open folder',
            compact: true,
            onTap: _openFolder,
          ),
          SettingsActionButton(
            label: 'Restore from this file…',
            compact: true,
            loading: _restoring,
            onTap: _restoreFromFile,
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Keep a copy somewhere else',
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A backup on the same disk goes when the disk does. The '
              'folder holds nothing but this file, so it can be a Git '
              'repository with a remote of your own:',
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: muted,
              ),
            ),
            const SizedBox(height: 8),
            _CodeBox(
              text:
                  'cd $dir\n'
                  'git init\n'
                  'git add $kTodoBackupFileName\n'
                  'git commit -m "Todo backup"',
            ),
            const SizedBox(height: 8),
            Text(
              'Commit again whenever you like — by hand, or from a timer. '
              'The file changes only when the board does, so each commit is '
              'exactly what changed.',
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ShellFontSizes.body,
          fontWeight: FontWeight.w600,
          color: theme.popupForeground,
        ),
      ),
    );
  }
}

/// A path or a command, set in monospace in a box of its own.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.divider),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: ShellFontSizes.secondary,
          color: theme.popupForeground,
        ),
      ),
    );
  }
}
