// The todo board's backups: where the backup file is and how to keep it
// somewhere safer, and the backup servers it is sent to.
//
// It owns no state of its own worth keeping. [TodoStore] writes the file and
// restores from it; [TodoRemoteBackup] owns the servers, their schedule and
// their results. This is the card over the board that shows both, and the form
// that adds or changes a server.

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
import 'package:moonswing/todo/todo_backup.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_remote_backup.dart';
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
    required this.remote,
    required this.onOpen,
  });

  final TodoStore store;
  final TodoRemoteBackup remote;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, remote]),
      builder: (context, _) {
        final error = store.backupError;
        final failing = remote.anyFailing;
        final servers = remote.servers.where((s) => s.enabled).length;
        final text = StringBuffer()
          ..write(
            error != null
                ? 'The backup file could not be written'
                : 'Backed up to ${displayPath(store.backupPath)}',
          );
        if (servers > 0) {
          text.write(
            failing
                ? ' · a backup server could not be reached'
                : servers == 1
                ? ' · and 1 server'
                : ' · and $servers servers',
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
    required this.remote,
    required this.onDone,
    this.copy = copyTextToClipboard,
    this.openFolder = _openFolder,
  });

  final TodoStore store;
  final TodoRemoteBackup remote;
  final VoidCallback onDone;

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
      // Absorbs clicks meant for the board underneath; not a dismiss, because
      // the server form may hold a draft.
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
                remote: remote,
                onDone: onDone,
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
    required this.remote,
    required this.onDone,
    required this.copy,
    required this.openFolder,
  });

  final TodoStore store;
  final TodoRemoteBackup remote;
  final VoidCallback onDone;
  final Future<ClipboardResult> Function(String text) copy;
  final bool Function(String directory) openFolder;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

/// Which server the form is open for: a new one, or an existing id.
typedef _Editing = ({String? id});

class _BackupCardState extends State<_BackupCard> {
  _Editing? _editing;

  /// The outcome of the last thing the user asked for — a copy, a restore, a
  /// backup now — said where they asked for it.
  String? _message;
  bool _messageIsError = false;
  bool _restoring = false;

  late final Listenable _both = Listenable.merge([widget.store, widget.remote]);

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

  Future<void> _backUpNow(BackupServer server) async {
    final error = await widget.remote.backUpNow(server.id);
    _say(error ?? 'Sent the board to ${server.label}.', error: error != null);
  }

  Future<void> _remove(BackupServer server) async {
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Remove ${server.label}?',
      message:
          'The board will no longer be sent there. Backups already on the '
          'server are left where they are.',
      confirmLabel: 'Remove',
    );
    if (confirmed) await widget.remote.remove(server.id);
  }

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
        listenable: _both,
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
              ..._buildServerSection(theme),
            ],
          ),
        ),
      ),
    );
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
              'exactly what changed. Or add a backup server below and the '
              'shell sends it for you.',
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

  List<Widget> _buildServerSection(ThemeConfig theme) {
    final remote = widget.remote;
    final editing = _editing;
    final muted = theme.popupForeground.withValues(alpha: 0.7);
    return [
      Row(
        children: [
          const Expanded(child: _Heading('Backup servers', bottom: 0)),
          if (editing == null)
            SettingsAddButton(
              label: 'Add server',
              onTap: () => setState(() => _editing = (id: null)),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'The backup file is sent to each server when the board has changed, '
        'at most as often as you choose. Any WebDAV folder works — '
        'Nextcloud, ownCloud, most NAS boxes, many hosted file services — '
        'as does any address that accepts an HTTP PUT. Passwords are kept '
        'in ${displayPath(remote.path)}, readable only by you.',
        style: TextStyle(fontSize: ShellFontSizes.secondary, color: muted),
      ),
      if (remote.fileError != null) ...[
        const SizedBox(height: 8),
        Text(
          remote.fileError!,
          style: const TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: kErrorColor,
          ),
        ),
      ],
      const SizedBox(height: 10),
      if (editing != null && editing.id == null)
        _ServerForm(
          key: const ValueKey('new server'),
          remote: remote,
          existing: null,
          onDone: () => setState(() => _editing = null),
        ),
      if (remote.servers.isEmpty && editing == null)
        const SettingsHint('No backup servers yet.'),
      for (final server in remote.servers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: editing?.id == server.id
              ? _ServerForm(
                  key: ValueKey('edit ${server.id}'),
                  remote: remote,
                  existing: server,
                  onDone: () => setState(() => _editing = null),
                )
              : _ServerRow(
                  server: server,
                  status: remote.status(server.id),
                  busy: remote.busy(server.id) || _restoring,
                  now: widget.store.now,
                  onToggle: (on) => remote.update(server.copyWith(enabled: on)),
                  onBackUp: () => _backUpNow(server),
                  onRestore: () => _restore(
                    () => remote.fetch(server.id),
                    from: 'on ${server.label}',
                  ),
                  onEdit: () => setState(() => _editing = (id: server.id)),
                  onRemove: () => _remove(server),
                ),
        ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.bottom = 6});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
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

/// One server: what it is, how its last attempt went, and what can be done
/// with it.
class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.status,
    required this.busy,
    required this.now,
    required this.onToggle,
    required this.onBackUp,
    required this.onRestore,
    required this.onEdit,
    required this.onRemove,
  });

  final BackupServer server;
  final BackupServerStatus status;
  final bool busy;
  final DateTime now;
  final ValueChanged<bool> onToggle;
  final VoidCallback onBackUp;
  final VoidCallback onRestore;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  String get _statusLine {
    if (!server.enabled) return 'Paused.';
    final error = status.lastError;
    if (error != null) return error;
    final success = status.lastSuccess;
    final when = success == null
        ? 'Not backed up yet'
        : 'Last backed up ${describeBackupMoment(success, now)}';
    return '$when · ${server.frequency.label.toLowerCase()} when the board '
        'changes.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final failing = server.enabled && status.lastError != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(
          color: failing ? kErrorColor.withValues(alpha: 0.5) : theme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FaIcon(
                FontAwesomeIcons.server,
                size: ShellFontSizes.caption,
                color: theme.accentText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  server.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SettingsToggle(value: server.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            server.fileUri?.toString() ?? server.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusLine,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: failing
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
                label: 'Back up now',
                compact: true,
                loading: busy,
                onTap: onBackUp,
              ),
              SettingsActionButton(
                label: 'Restore…',
                compact: true,
                enabled: !busy,
                onTap: onRestore,
              ),
              SettingsActionButton(label: 'Edit', compact: true, onTap: onEdit),
              SettingsActionButton(
                label: 'Remove',
                compact: true,
                onTap: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Adds a server, or changes one. Nothing is saved until Save.
class _ServerForm extends StatefulWidget {
  const _ServerForm({
    super.key,
    required this.remote,
    required this.existing,
    required this.onDone,
  });

  final TodoRemoteBackup remote;
  final BackupServer? existing;
  final VoidCallback onDone;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.existing?.url ?? '',
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  late BackupFrequency _frequency =
      widget.existing?.frequency ?? BackupFrequency.hourly;
  late bool _keepDaily = widget.existing?.keepDaily ?? true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _error {
    final url = _url.text.trim();
    if (url.isEmpty) return null;
    if (remoteBackupFileUri(url) == null) {
      return 'The address has to start with https:// (or http://).';
    }
    return null;
  }

  bool get _valid => _url.text.trim().isNotEmpty && _error == null && !_saving;

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    if (existing == null) {
      await widget.remote.add(
        name: _name.text,
        url: _url.text,
        username: _user.text,
        password: _password.text,
        frequency: _frequency,
        keepDaily: _keepDaily,
      );
    } else {
      await widget.remote.update(
        existing.copyWith(
          name: _name.text.trim(),
          url: _url.text.trim(),
          username: _user.text,
          password: _password.text,
          frequency: _frequency,
          keepDaily: _keepDaily,
        ),
      );
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final error = _error;
    final target = remoteBackupFileUri(_url.text);
    final muted = theme.popupForeground.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Name'),
          SettingsTextField(
            controller: _name,
            hint: 'Home NAS',
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          const _FieldLabel('Folder address'),
          SettingsTextField(
            controller: _url,
            autofocus: widget.existing == null,
            hint: 'https://cloud.example.com/remote.php/dav/files/me/Backups/',
            onChanged: (_) {},
          ),
          const SizedBox(height: 4),
          Text(
            error ??
                (target == null
                    ? 'A WebDAV folder; the board is saved in it as '
                          '$kRemoteBackupFileName. An address ending in .json '
                          'is used as the file itself.'
                    : 'Saved as $target'),
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: error != null ? kErrorColor : muted,
            ),
          ),
          if (remoteBackupIsInsecure(_url.text)) ...[
            const SizedBox(height: 4),
            const Text(
              'An http:// address sends the password and the board '
              'unencrypted. Use https:// unless the server is on a network '
              'you trust.',
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: kErrorColor,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('User name'),
                    SettingsTextField(controller: _user, onChanged: (_) {}),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('Password'),
                    SettingsTextField(
                      controller: _password,
                      obscureText: true,
                      hint: 'An app password, ideally',
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _FieldLabel('How often'),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 200,
              child: SettingsDropdown<BackupFrequency>(
                items: [
                  for (final f in BackupFrequency.values)
                    SettingsDropdownItem(value: f, label: f.label),
                ],
                selected: _frequency,
                onSelected: (f) => setState(() => _frequency = f),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Only when the board has changed since the last copy was sent.',
            style: TextStyle(fontSize: ShellFontSizes.secondary, color: muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('Keep a copy for each day', bottom: 2),
                    Text(
                      'Also saves moonswing-todo-YYYY-MM-DD.json, so a board '
                      'emptied by mistake is not the only copy there.',
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SettingsToggle(
                value: _keepDaily,
                onChanged: (v) => setState(() => _keepDaily = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 90,
                child: SettingsActionButton(
                  label: 'Cancel',
                  onTap: widget.onDone,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: SettingsActionButton(
                  label: 'Save',
                  primary: true,
                  enabled: _valid,
                  loading: _saving,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.bottom = 6});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          fontWeight: FontWeight.w600,
          color: theme.popupForeground.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
