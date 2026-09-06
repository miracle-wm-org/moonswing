// An in-app file picker rendered inside the shell's own overlay window.
//
// The OS-native picker (`file_selector`) opens a separate top-level window,
// which the compositor stacks *behind* the layer-shell panels — unusable. This
// renders a themed modal into the settings overlay's root [Overlay] instead, so
// it always appears on top of the panel.
//
// Deliberately general: [showFilePicker] takes a list of [FilePickerFilter]s and
// a multi-select flag, so any settings surface can reuse it.
//
// Two things about how it is *read*. The right pane has two forms — tiles for
// picking a wallpaper, a line-by-line list for reading a name — because neither
// is right for both jobs. And the toolbar's search filters the folder being
// browsed and nothing else: the tree is how you change folder, so a filter
// reaching across the filesystem would be a slower way to navigate. Ctrl+F
// focuses it from anywhere in the dialog.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xdg_icons/xdg_icons.dart';

import 'package:graceful_shell/root_modal.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup_transition.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/overlay/file_picker_controller.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/format.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';

/// A named set of file extensions the picker will show. An empty [extensions]
/// set matches every file ("All files"). Extensions are stored with a leading
/// dot and matched case-insensitively, mirroring [isImagePath] in
/// `lib/media_paths.dart`.
class FilePickerFilter {
  const FilePickerFilter({required this.label, required this.extensions});

  final String label;
  final Set<String> extensions;

  /// Whether [path] passes this filter, judged purely by its extension.
  bool matches(String path) {
    if (extensions.isEmpty) return true;
    final lower = path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return false;
    return extensions.contains(lower.substring(dot));
  }

  /// Images the running shell can use as wallpaper — the same set `config.dart`
  /// validates against, so the picker and the shell never disagree.
  static final FilePickerFilter images =
      FilePickerFilter(label: 'Images', extensions: imageExtensions);

  /// Videos the shell can play behind a surface, for the lock screen and any
  /// other wallpaper that accepts motion.
  static final FilePickerFilter videos =
      FilePickerFilter(label: 'Videos', extensions: videoExtensions);

  /// Images *and* videos, for wallpapers that accept either.
  static final FilePickerFilter wallpapers = FilePickerFilter(
    label: 'Images & video',
    extensions: {...imageExtensions, ...videoExtensions},
  );

  /// Desktop entries, for pinning an application to the desktop grid.
  static const FilePickerFilter desktopEntries =
      FilePickerFilter(label: 'Applications', extensions: {'.desktop'});

  /// Matches everything, for pickers that should not constrain by type.
  static const FilePickerFilter all =
      FilePickerFilter(label: 'All files', extensions: {});
}

/// Opens the in-app file picker and resolves to the chosen absolute paths, or
/// `null` if the user cancelled (Escape, the scrim, or Cancel).
///
/// The modal is inserted into the root [Overlay] so a nested [Navigator]'s
/// clipped overlay cannot cut it off.
Future<List<String>?> showFilePicker(
  BuildContext context, {
  required List<FilePickerFilter> filters,
  bool allowMultiple = true,
  bool allowDirectories = false,
  String? initialDirectory,
}) {
  return showRootModal<List<String>?>(
    context,
    (close) => _FilePickerDialog(
      filters: filters.isEmpty ? const [FilePickerFilter.all] : filters,
      allowMultiple: allowMultiple,
      allowDirectories: allowDirectories,
      initialDirectory: initialDirectory,
      onResult: close,
    ),
  );
}

// ---------------------------------------------------------------------------
// Pure filesystem helpers (widget-free, so tests point them at a temp dir).
// ---------------------------------------------------------------------------

/// The last path segment of [path], tolerant of a trailing slash. `/` → `/`.
String basenameOf(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf('/');
  if (i < 0) return p;
  final name = p.substring(i + 1);
  return name.isEmpty ? '/' : name;
}

/// Lists [path], swallowing permission/IO errors as an empty list, and hiding
/// dot-entries unless [showHidden]. Synchronous, following the `process_reader`
/// precedent — the directories a picker opens are small.
List<FileSystemEntity> readDir(String path, {bool showHidden = false}) {
  try {
    final entries = Directory(path).listSync(followLinks: false);
    if (showHidden) return entries;
    return entries
        .where((e) => !basenameOf(e.path).startsWith('.'))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Orders [entries] directories-first, then files, each case-insensitive by
/// name. Symlinks sort as files.
List<FileSystemEntity> sortEntries(List<FileSystemEntity> entries) {
  int byName(FileSystemEntity a, FileSystemEntity b) => basenameOf(a.path)
      .toLowerCase()
      .compareTo(basenameOf(b.path).toLowerCase());
  final dirs = entries.whereType<Directory>().toList()..sort(byName);
  final files =
      entries.where((e) => e is! Directory).toList()..sort(byName);
  return [...dirs, ...files];
}

/// The child directories of [path], sorted case-insensitively — the tree's
/// lazy expansion payload.
List<Directory> subDirs(String path, {bool showHidden = false}) {
  final dirs = readDir(path, showHidden: showHidden).whereType<Directory>().toList();
  dirs.sort((a, b) =>
      basenameOf(a.path).toLowerCase().compareTo(basenameOf(b.path).toLowerCase()));
  return dirs;
}

/// A Font Awesome glyph for a file, keyed on its extension. General-purpose —
/// not limited to the wallpaper use case.
FaIconData iconForFile(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final ext = dot < 0 ? '' : lower.substring(dot);
  switch (ext) {
    case '.jpg':
    case '.jpeg':
    case '.png':
    case '.webp':
    case '.gif':
    case '.bmp':
    case '.svg':
    case '.tiff':
    case '.ico':
      return FontAwesomeIcons.fileImage;
    case '.mp4':
    case '.mkv':
    case '.webm':
    case '.mov':
    case '.avi':
    case '.m4v':
      return FontAwesomeIcons.fileVideo;
    case '.mp3':
    case '.flac':
    case '.wav':
    case '.ogg':
    case '.m4a':
    case '.opus':
      return FontAwesomeIcons.fileAudio;
    case '.pdf':
      return FontAwesomeIcons.filePdf;
    case '.zip':
    case '.tar':
    case '.gz':
    case '.xz':
    case '.7z':
    case '.rar':
    case '.bz2':
    case '.zst':
      return FontAwesomeIcons.fileZipper;
    case '.txt':
    case '.md':
    case '.rst':
    case '.log':
      return FontAwesomeIcons.fileLines;
    case '.dart':
    case '.js':
    case '.ts':
    case '.py':
    case '.c':
    case '.cpp':
    case '.h':
    case '.hpp':
    case '.rs':
    case '.go':
    case '.java':
    case '.sh':
    case '.html':
    case '.css':
    case '.json':
    case '.yaml':
    case '.yml':
    case '.toml':
    case '.xml':
      return FontAwesomeIcons.fileCode;
    default:
      return FontAwesomeIcons.file;
  }
}

/// How the right-hand pane draws what is in the current folder.
///
/// Two forms because the two jobs want different things: a wallpaper is chosen by
/// looking at it, a config file by reading its name, size and date. Tiles show
/// four names in the width a list shows one; the list shows twenty rows in the
/// height tiles show six.
enum FilePickerViewMode {
  /// The thumbnail grid — the default, and what an image filter wants.
  tiles,

  /// One line per entry, with size and modified date.
  list,
}

/// One row of a directory listing, with the [FileStat] fields the list form
/// prints already read.
///
/// Statted once per directory read rather than once per build: the pane rebuilds
/// on every keystroke, and a `statSync` per visible row per keystroke is a
/// syscall storm for two columns of grey text.
@immutable
class PickerEntry {
  const PickerEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String path;
  final bool isDirectory;

  /// Bytes, or -1 when there is no meaningful answer — a directory, or an
  /// entry whose stat failed (a dangling symlink, a permission the walk has
  /// but the stat does not).
  final int size;

  /// Last modification, or null when the stat failed. Null rather than the
  /// epoch, so a row with no answer prints nothing instead of `1970-01-01`.
  final DateTime? modified;

  String get name => basenameOf(path);
}

/// Lists [path] as [PickerEntry]s, directories first, each group sorted
/// case-insensitively by name.
///
/// Symlinks are skipped, which is [readDir]'s `followLinks: false` showing
/// through: the pane has only ever rendered files and directories.
List<PickerEntry> listDirectory(String path, {bool showHidden = false}) {
  return [
    for (final entity in sortEntries(readDir(path, showHidden: showHidden)))
      if (entity is Directory || entity is File) _statEntry(entity),
  ];
}

PickerEntry _statEntry(FileSystemEntity entity) {
  final isDirectory = entity is Directory;
  var size = -1;
  DateTime? modified;
  try {
    final stat = entity.statSync();
    // `statSync` reports a failure as `notFound` rather than by throwing, and
    // leaves the other fields invalid — reading them is what would print an
    // epoch date under a file the picker cannot see.
    if (stat.type != FileSystemEntityType.notFound) {
      modified = stat.modified;
      if (!isDirectory) size = stat.size;
    }
  } catch (_) {
    // Left as the "no answer" pair.
  }
  return PickerEntry(
    path: entity.path,
    isDirectory: isDirectory,
    size: size,
    modified: modified,
  );
}

/// Whether [name] matches the search [query].
///
/// Every whitespace-separated token has to appear somewhere in the name, in any
/// order and case-insensitively — so `sun 4k` finds `4K-sunset-02.png`, which a
/// single substring match would not. An empty query matches everything.
bool matchesSearch(String name, String query) {
  final tokens =
      query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return true;
  final lower = name.toLowerCase();
  return tokens.every((token) => lower.contains(token));
}

/// The entries the right-hand pane shows: [filter] applied to files, folders
/// kept only when they are selectable, and [query] applied to both.
///
/// The type filter deliberately does not reach folders — a folder has no
/// extension to match — but the *search* does: a name is a name.
List<PickerEntry> filterEntries(
  List<PickerEntry> entries, {
  required FilePickerFilter filter,
  required bool includeDirectories,
  String query = '',
}) {
  return [
    for (final entry in entries)
      if (entry.isDirectory ? includeDirectories : filter.matches(entry.path))
        if (matchesSearch(entry.name, query)) entry,
  ];
}

/// The size column: a folder says so, an unreadable entry says nothing, and a
/// file gets `formatBytes` — the shell's one byte formatter, borrowed from the
/// system monitor rather than spelled a second time here.
String formatEntrySize(PickerEntry entry) {
  if (entry.isDirectory) return 'Folder';
  if (entry.size < 0) return '';
  return formatBytes(entry.size);
}

/// The modified column: `14:32` for something changed today, `2026-08-26`
/// otherwise.
///
/// ISO rather than `26 Aug` because this is a column of dates read against each
/// other, where sortable order and a fixed width are worth more — and because it
/// needs no month table, which `lib/moon/moon_format.dart` owns and has no
/// business lending to a file picker.
String formatEntryModified(DateTime when, {required DateTime now}) {
  if (when.year == now.year &&
      when.month == now.month &&
      when.day == now.day) {
    final hour = when.hour.toString().padLeft(2, '0');
    final minute = when.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final month = when.month.toString().padLeft(2, '0');
  final day = when.day.toString().padLeft(2, '0');
  return '${when.year}-$month-$day';
}

String get _homeDir => Platform.environment['HOME'] ?? '/';

/// The width of the folder tree. Wide enough for a couple of levels of
/// indentation plus a name, which is what the old 220 was one indent short of.
const double _kTreePaneWidth = 240;

/// The height of both panes' header strips — the tree's label and the file
/// pane's toolbar. One constant because the two dividers under them have to
/// line up across the card's vertical rule; two would drift apart.
const double _kPaneHeaderHeight = 56;

/// One row of the list form. Fixed, so the list is an `itemExtent` builder
/// rather than a column of measured rows.
const double _kListRowHeight = 38;

/// The form the picker last opened in, for the life of the process.
///
/// Not config and not persisted: this is chrome state like the OSD's. It is
/// remembered at all because adding three wallpapers is three opens of this
/// dialog, and re-pressing the toggle on each is the friction a modal is judged
/// by.
FilePickerViewMode _stickyViewMode = FilePickerViewMode.tiles;

const double _kTileWidth = 148;
const double _kTileThumbHeight = 96;

// ---------------------------------------------------------------------------
// The dialog.
// ---------------------------------------------------------------------------

class _FilePickerDialog extends StatefulWidget {
  const _FilePickerDialog({
    required this.filters,
    required this.allowMultiple,
    required this.allowDirectories,
    required this.initialDirectory,
    required this.onResult,
  });

  final List<FilePickerFilter> filters;
  final bool allowMultiple;

  /// Whether folders are pickable results, not just navigation.
  ///
  /// Off by default: every existing caller wants a file, and the tree already
  /// serves folders as the way to get there. The desktop grid's "Add file or
  /// folder…" is what needs them selectable.
  final bool allowDirectories;

  final String? initialDirectory;
  final ValueChanged<List<String>?> onResult;

  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  late String _currentDir;
  int _filterIndex = 0;
  bool _showHidden = false;
  FilePickerViewMode _viewMode = _stickyViewMode;
  final Set<String> _expanded = {};
  final Set<String> _selected = {};

  /// The current folder, statted once per read rather than per build — see
  /// [PickerEntry]. Reloaded from [_reloadEntries] and nowhere else, so a
  /// listing is never a side effect of a `build`.
  List<PickerEntry> _entries = const [];

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'file-picker-search');

  /// The search text, as a notifier rather than `setState` state.
  ///
  /// Every keystroke re-filters the file pane and nothing else, and the tree pane
  /// is the expensive half: each expanded node lists its own children on build,
  /// so a `setState` per character would walk the open branch of the filesystem
  /// once per keypress. Only the pane body, the footer's counts and the field's
  /// clear button listen.
  final _query = ValueNotifier<String>('');

  /// Roots shown at the top of the tree: the user's home and the filesystem
  /// root. Home is deduped away when it *is* `/`.
  late final List<(String path, String label)> _roots = _homeDir == '/'
      ? const [('/', 'Filesystem')]
      : [(_homeDir, 'Home'), ('/', 'Filesystem')];

  FilePickerFilter get _filter => widget.filters[_filterIndex];

  @override
  void initState() {
    super.initState();
    final start = widget.initialDirectory ?? _homeDir;
    _currentDir = Directory(start).existsSync() ? start : _homeDir;
    // Reveal the current directory by expanding it and every ancestor up to a
    // known root, so the tree opens already scrolled to something useful.
    for (final (root, _) in _roots) {
      if (_currentDir == root || _currentDir.startsWith('$root/') || root == '/') {
        var p = _currentDir;
        while (p.length >= root.length && p.startsWith(root)) {
          _expanded.add(p);
          if (p == root) break;
          final parent = Directory(p).parent.path;
          if (parent == p) break;
          p = parent;
        }
      }
    }
    _reloadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  void _reloadEntries() =>
      _entries = listDirectory(_currentDir, showHidden: _showHidden);

  void _selectDir(String path) {
    setState(() {
      _currentDir = path;
      _expanded.add(path);
      _reloadEntries();
    });
    // A search is scoped to one folder, so changing folder ends it — carrying
    // the query across would land the user in a folder showing a fraction of
    // what is in it, with the reason two panes away.
    _clearSearch();
  }

  void _setShowHidden(bool value) {
    setState(() {
      _showHidden = value;
      _reloadEntries();
    });
  }

  void _toggleExpand(String path) {
    setState(() {
      if (!_expanded.remove(path)) _expanded.add(path);
    });
  }

  void _toggleFile(String path) {
    setState(() {
      if (widget.allowMultiple) {
        if (!_selected.remove(path)) _selected.add(path);
      } else {
        _selected
          ..clear()
          ..add(path);
      }
    });
  }

  /// Focuses the search field and selects what is in it, so Ctrl+F on an
  /// existing query starts a new one rather than appending to it.
  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _query.value = '';
  }

  void _confirm() {
    // With nothing ticked, "Use this folder" means the folder being browsed —
    // otherwise reaching a directory you cannot see a tile for (the root, say)
    // would be a dead end.
    if (_selected.isEmpty) {
      if (widget.allowDirectories) widget.onResult([_currentDir]);
      return;
    }
    widget.onResult(_selected.toList());
  }

  /// Ctrl+F starts a search and Escape ends one; only an Escape with nothing to
  /// end closes the dialog.
  ///
  /// Two-stage because a search is a state the user is *in*: pressing Escape to
  /// leave a filtered folder and having the whole picker vanish is the same
  /// surprise as a browser closing its tab. Both arrive here from anywhere in the
  /// card, since key events walk up from the focused node and this [Focus] is an
  /// ancestor of every one.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      _focusSearch();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_query.value.isNotEmpty) {
        _clearSearch();
        return KeyEventResult.handled;
      }
      widget.onResult(null);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onResult(null),
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Roomier than it was: the list form wants a name column that
                  // is not the first thing to be ellipsised, and the tile form
                  // wants a row of four rather than three.
                  final w = (constraints.maxWidth * 0.9).clamp(360.0, 900.0);
                  final h = (constraints.maxHeight * 0.9).clamp(340.0, 640.0);
                  return PopupTransition(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: _card(context, theme),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ThemeConfig theme) {
    return Container(
      decoration: BoxDecoration(
        // Opaque inside the settings page, where this card covers the pane it
        // was opened from. See [OpaquePopupScope].
        color: OpaquePopupScope.fill(context, theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme),
          _rule(theme),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _kTreePaneWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _kPaneHeaderHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: const SettingsSectionLabel('Folders'),
                          ),
                        ),
                      ),
                      _rule(theme),
                      Expanded(child: _treePane()),
                    ],
                  ),
                ),
                Container(width: 1, color: theme.divider),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _kPaneHeaderHeight,
                        child: _toolbar(theme),
                      ),
                      _rule(theme),
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _query,
                          builder: (context, query, _) =>
                              _paneBody(theme, query),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _rule(theme),
          _footer(theme),
        ],
      ),
    );
  }

  Widget _rule(ThemeConfig theme) => Container(height: 1, color: theme.divider);

  /// What the current folder is called: the two roots by their own names, and
  /// everything else by its last segment.
  String get _folderTitle {
    if (_currentDir == '/') return 'Filesystem';
    if (_currentDir == _homeDir) return 'Home';
    return basenameOf(_currentDir);
  }

  /// The current path with the home prefix folded to `~`, the way most file
  /// managers show it.
  String get _folderPath {
    if (_homeDir != '/' && _currentDir.startsWith(_homeDir)) {
      final rest = _currentDir.substring(_homeDir.length);
      return rest.isEmpty ? '~' : '~$rest';
    }
    return _currentDir;
  }

  Widget _header(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Row(
        children: [
          // Two lines rather than one: the folder's *name* is what the eye
          // needs off the top of the card, and the path under it is the answer
          // to "which one is that?" — a single ellipsised path line was the
          // question and the answer competing for the same 13px.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _folderTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    fontWeight: FontWeight.w600,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _folderPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          if (widget.filters.length > 1) ...[
            SettingsSegmented(
              options: [for (final f in widget.filters) f.label],
              value: _filter.label,
              onChanged: (label) => setState(() =>
                  _filterIndex = widget.filters.indexWhere((f) => f.label == label)),
            ),
            const SizedBox(width: 14),
          ],
          _HiddenToggle(value: _showHidden, onChanged: _setShowHidden),
          const SizedBox(width: 2),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: 13,
            onTap: () => widget.onResult(null),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SettingsTextField(
              controller: _searchController,
              focusNode: _searchFocus,
              hint: 'Search in $_folderTitle (Ctrl+F)',
              onChanged: (value) => _query.value = value,
              leading: FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                size: 12,
                color: theme.popupForeground.withValues(alpha: 0.45),
              ),
              // Always a widget, never null: swapping `trailing` between null
              // and a button restructures the field around the [EditableText],
              // which re-inflates it and drops the focus the user is typing
              // into. A spacer of the button's own size keeps the row put.
              trailing: ValueListenableBuilder<String>(
                valueListenable: _query,
                builder: (context, query, _) => query.isEmpty
                    ? const SizedBox.square(
                        dimension: ShellSizes.iconButtonDense,
                      )
                    : SettingsIconButton(
                        icon: FontAwesomeIcons.xmark,
                        size: 10,
                        box: ShellSizes.iconButtonDense,
                        onTap: _clearSearch,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _ViewModeToggle(
            mode: _viewMode,
            onChanged: (mode) => setState(() {
              _viewMode = mode;
              _stickyViewMode = mode;
            }),
          ),
        ],
      ),
    );
  }

  Widget _treePane() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (path, label) in _roots)
            _TreeNode(
              path: path,
              label: label,
              depth: 0,
              expanded: _expanded,
              currentDir: _currentDir,
              showHidden: _showHidden,
              onSelect: _selectDir,
              onToggle: _toggleExpand,
            ),
        ],
      ),
    );
  }

  /// What the current folder holds, after the type filter and the search.
  List<PickerEntry> _visible(String query) => filterEntries(
        _entries,
        filter: _filter,
        includeDirectories: widget.allowDirectories,
        query: query,
      );

  Widget _paneBody(ThemeConfig theme, String query) {
    final visible = _visible(query);
    if (visible.isEmpty) return _emptyState(theme, query);
    return _viewMode == FilePickerViewMode.tiles
        ? _tilePane(visible)
        : _listPane(visible);
  }

  Widget _emptyState(ThemeConfig theme, String query) {
    final searching = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              searching
                  ? 'Nothing here matches “$query”.'
                  : (widget.allowDirectories
                      ? 'Nothing to select in this folder.'
                      : 'No matching files in this folder.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
            if (searching) ...[
              const SizedBox(height: 16),
              SettingsOptionButton(
                label: 'Clear search',
                selected: false,
                onTap: _clearSearch,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tilePane(List<PickerEntry> visible) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Wrap(
        spacing: 14,
        runSpacing: 18,
        children: [
          for (final entry in visible)
            _FileTile(
              entry: entry,
              selected: _selected.contains(entry.path),
              onTap: () => _toggleFile(entry.path),
            ),
        ],
      ),
    );
  }

  Widget _listPane(List<PickerEntry> visible) {
    // One clock for the whole list, so two rows written a second apart cannot
    // disagree about what "today" is.
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        // The two grey columns are the first thing to go when the pane is
        // narrow: a name half-ellipsised beside a size nobody asked for is the
        // wrong trade, and the card's own minimum width leaves this pane
        // barely wider than a tile.
        final showSize = constraints.maxWidth >= 300;
        final showModified = constraints.maxWidth >= 420;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemExtent: _kListRowHeight,
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final entry = visible[i];
            return _FileRow(
              entry: entry,
              selected: _selected.contains(entry.path),
              showSize: showSize,
              showModified: showModified,
              now: now,
              onTap: () => _toggleFile(entry.path),
            );
          },
        );
      },
    );
  }

  Widget _footer(ThemeConfig theme) {
    final muted = theme.popupForeground.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _query,
              builder: (context, query, _) {
                final visible = _visible(query).length;
                final total = _visible('').length;
                final noun = total == 1 ? 'item' : 'items';
                final counts = query.isEmpty
                    ? '$total $noun'
                    : '$visible of $total match';
                final selection = _selected.isEmpty
                    ? (widget.allowDirectories ? _folderTitle : 'Nothing selected')
                    : '${_selected.length} selected';
                return Text(
                  '$selection  ·  $counts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontFamily: theme.fontFamily,
                    color: muted,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 20),
          SettingsOptionButton(
            label: 'Cancel',
            selected: false,
            onTap: () => widget.onResult(null),
          ),
          const SizedBox(width: 10),
          // The confirm button reads disabled (dimmed, no-op) until something is
          // selected — reusing SettingsOptionButton keeps it in the app's idiom.
          Opacity(
            // Never dimmed when folders are allowed: an empty selection then
            // means "use the folder I am in", which is a real answer.
            opacity: _selected.isEmpty && !widget.allowDirectories ? 0.4 : 1.0,
            child: SettingsOptionButton(
              label: _selected.isEmpty && widget.allowDirectories
                  ? 'Use this folder'
                  : (widget.allowMultiple ? 'Add' : 'Select'),
              selected: _selected.isNotEmpty || widget.allowDirectories,
              onTap: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-screen file picker for a window of its own.
///
/// [showFilePicker] inserts into the nearest root [Overlay], which the desktop
/// surface has none of — and could not usefully have, being on the background
/// layer under every application window. The root creates an overlay-layer window
/// and renders this into it; `FilePickerController` is the seam.
class FilePickerWindow extends StatelessWidget {
  const FilePickerWindow({
    super.key,
    required this.request,
    required this.onResult,
  });

  final FilePickerRequest request;
  final ValueChanged<List<String>?> onResult;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      // The shell boots without a WidgetsApp, so the default text-editing key
      // bindings are absent — the same trap `SettingsOverlay` documents. The
      // search field needs them: without this its Backspace, arrows and
      // select-all would all be dead keys.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: ShellFontSizes.label,
            color: theme.popupForeground,
          ),
          // Built directly rather than through showFilePicker: there is no
          // pre-existing Overlay to insert into here, this *is* the window.
          child: _FilePickerDialog(
            filters: request.filters.isEmpty
                ? const [FilePickerFilter.all]
                : request.filters,
            allowMultiple: request.allowMultiple,
            allowDirectories: request.allowDirectories,
            initialDirectory: request.initialDirectory,
            onResult: onResult,
          ),
        ),
      ),
    );
  }
}

/// The tiles-or-list switch, in the file pane's own toolbar.
///
/// Two icons in one bordered box rather than two loose buttons, so the pair reads
/// as one control with a state. Deliberately not [SettingsSegmented], which
/// spells its options as words: "Tiles"/"List" beside a search field is two
/// labels' worth of chrome for a thing whose glyphs say it.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final FilePickerViewMode mode;
  final ValueChanged<FilePickerViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(theme, FilePickerViewMode.tiles,
              FontAwesomeIcons.tableCellsLarge, 'Tiles'),
          const SizedBox(width: 2),
          _segment(
              theme, FilePickerViewMode.list, FontAwesomeIcons.listUl, 'List'),
        ],
      ),
    );
  }

  Widget _segment(
    ThemeConfig theme,
    FilePickerViewMode value,
    FaIconData icon,
    String label,
  ) {
    final active = mode == value;
    return Semantics(
      label: label,
      selected: active,
      button: true,
      child: HoverRegion(
        onTap: () => onChanged(value),
        builder: (context, hovered) => Container(
          width: 32,
          height: ShellSizes.minTapTarget,
          decoration: BoxDecoration(
            color: active
                ? theme.accent
                : (hovered ? theme.surfaceHover : const Color(0x00000000)),
            borderRadius: BorderRadius.circular(ShellRadii.barButton),
          ),
          alignment: Alignment.center,
          child: FaIcon(
            icon,
            size: 12,
            color: active
                ? kOnAccent
                : theme.popupForeground.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

/// A single row in the directory tree, plus (when expanded) its child rows.
///
/// The tree's expansion/selection state lives in [_FilePickerDialogState]; this
/// node reads it and rebuilds when the dialog does. Children are listed lazily.
///
/// The node is stateless and the hover highlight lives in [_TreeRow], so hovering
/// a row rebuilds *only that row* — otherwise every pointer move would re-list
/// the directory and rebuild the whole child subtree.
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    super.key,
    required this.path,
    required this.depth,
    required this.expanded,
    required this.currentDir,
    required this.showHidden,
    required this.onSelect,
    required this.onToggle,
    this.label,
  });

  final String path;
  final String? label;
  final int depth;
  final Set<String> expanded;
  final String currentDir;
  final bool showHidden;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final isExpanded = expanded.contains(path);
    final row = _TreeRow(
      path: path,
      label: label,
      depth: depth,
      isExpanded: isExpanded,
      isCurrent: currentDir == path,
      onSelect: onSelect,
      onToggle: onToggle,
    );

    if (!isExpanded) return row;

    final children = subDirs(path, showHidden: showHidden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final dir in children)
          _TreeNode(
            key: ValueKey(dir.path),
            path: dir.path,
            depth: depth + 1,
            expanded: expanded,
            currentDir: currentDir,
            showHidden: showHidden,
            onSelect: onSelect,
            onToggle: onToggle,
          ),
      ],
    );
  }
}

/// A single tappable directory row. Owns its own hover state so a pointer move
/// repaints just this row, not the tree beneath it.
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.path,
    required this.label,
    required this.depth,
    required this.isExpanded,
    required this.isCurrent,
    required this.onSelect,
    required this.onToggle,
  });

  final String path;
  final String? label;
  final int depth;
  final bool isExpanded;
  final bool isCurrent;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final name = label ?? basenameOf(path);

    return HoverRegion(
      onTap: () => onSelect(path),
      builder: (context, hovered) => Container(
        color: isCurrent
            ? theme.accent.withValues(alpha: 0.22)
            : (hovered ? theme.surfaceHover.withValues(alpha: 0.16) : null),
        padding: EdgeInsets.only(
          left: 10.0 + depth * 16,
          right: 10,
          top: 7,
          bottom: 7,
        ),
        child: Row(
          children: [
            // The chevron is its own target inside the row's: tapping it opens
            // the branch without changing folder.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(path),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: FaIcon(
                    isExpanded
                        ? FontAwesomeIcons.chevronDown
                        : FontAwesomeIcons.chevronRight,
                    size: 9,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            XdgIcon(
              name: isCurrent || isExpanded ? 'folder-open' : 'folder',
              size: 16,
              iconNotFoundBuilder: () => FaIcon(
                isCurrent || isExpanded
                    ? FontAwesomeIcons.folderOpen
                    : FontAwesomeIcons.solidFolder,
                size: 13,
                color: theme.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: isCurrent
                      ? theme.popupForeground
                      : theme.popupForeground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The thumbnail an image entry draws, and the type icon everything else does.
///
/// Shared by the tile and the row so the two forms cannot disagree about what a
/// `.webp` looks like — the only difference between them is how big it is.
class _EntryThumb extends StatelessWidget {
  const _EntryThumb({
    required this.entry,
    required this.size,
    required this.iconSize,
    required this.radius,
    this.fill = true,
  });

  final PickerEntry entry;
  final Size size;
  final double iconSize;
  final double radius;

  /// Whether the icon sits on a filled plate (the tile) or on the row's own
  /// background (the list).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final icon = Center(
      child: FaIcon(
        entry.isDirectory ? FontAwesomeIcons.solidFolder : iconForFile(entry.path),
        size: iconSize,
        color: entry.isDirectory
            ? theme.accent
            : theme.popupForeground.withValues(alpha: 0.55),
      ),
    );
    final plate = fill ? ColoredBox(color: theme.controlSurface, child: icon) : icon;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: !entry.isDirectory && isImagePath(entry.path)
            ? Image.file(
                File(entry.path),
                fit: BoxFit.cover,
                // Decoded to roughly twice the box, which is enough for a
                // sharp thumbnail and a small fraction of the full image.
                cacheWidth: (size.width * 2).round(),
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => plate,
              )
            : plate,
      ),
    );
  }
}

/// The accent tick a selected entry carries.
class _SelectedTick extends StatelessWidget {
  const _SelectedTick({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: FaIcon(
        FontAwesomeIcons.check,
        size: diameter * 0.5,
        color: kOnAccent,
      ),
    );
  }
}

/// A file entry in the right pane's tile form: an image thumbnail when the file
/// is an image, otherwise a type icon, with the name below and an accent check
/// when selected.
class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final PickerEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => SizedBox(
        width: _kTileWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _kTileThumbHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _EntryThumb(
                    entry: entry,
                    size: const Size(_kTileWidth, _kTileThumbHeight),
                    iconSize: 30,
                    radius: ShellRadii.control,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ShellRadii.control),
                      border: Border.all(
                        color: selected
                            ? theme.accent
                            : (hovered ? theme.surfaceHover : theme.divider),
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: _SelectedTick(diameter: 20),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.25,
                fontFamily: theme.fontFamily,
                color: selected
                    ? theme.popupForeground
                    : theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file entry in the right pane's list form: one line, with the name given the
/// room and the size and date set quietly beside it.
///
/// Two lines' worth of information in one line's height is the point of this
/// form.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.showSize,
    required this.showModified,
    required this.now,
    required this.onTap,
  });

  final PickerEntry entry;
  final bool selected;
  final bool showSize;
  final bool showModified;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final muted = theme.popupForeground.withValues(alpha: 0.5);
    final modified = entry.modified;

    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShellRadii.control),
          color: selected
              ? theme.accent.withValues(alpha: 0.22)
              : (hovered
                  ? theme.surfaceHover.withValues(alpha: 0.16)
                  : const Color(0x00000000)),
        ),
        child: Row(
          children: [
            _EntryThumb(
              entry: entry,
              size: const Size(22, 22),
              iconSize: 13,
              radius: ShellRadii.barButton,
              fill: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: theme.popupForeground.withValues(
                    alpha: selected ? 1.0 : 0.88,
                  ),
                ),
              ),
            ),
            if (showSize) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 62,
                child: Text(
                  formatEntrySize(entry),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    fontFamily: theme.fontFamily,
                    color: muted,
                  ),
                ),
              ),
            ],
            if (showModified) ...[
              const SizedBox(width: 14),
              SizedBox(
                width: 82,
                child: Text(
                  modified == null
                      ? ''
                      : formatEntryModified(modified, now: now),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    fontFamily: theme.fontFamily,
                    color: muted,
                    // Tabular figures would be better still; the shell's fonts
                    // are the user's, so the fixed column width does that job.
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 18,
              child: selected
                  ? const Center(child: _SelectedTick(diameter: 16))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small "show hidden" eye toggle for the header.
///
/// The icon-button idiom itself is [SettingsIconButton]'s; this carries only
/// the eye's own rule, that an *active* toggle stays accented whether or not
/// the pointer is on it.
class _HiddenToggle extends StatelessWidget {
  const _HiddenToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsIconButton(
      icon: value ? FontAwesomeIcons.solidEye : FontAwesomeIcons.solidEyeSlash,
      size: 13,
      color: value
          ? theme.accent
          : theme.popupForeground.withValues(alpha: 0.6),
      onTap: () => onChanged(!value),
    );
  }
}
