// An in-app file picker rendered inside the shell's own overlay window.
//
// The OS-native picker (`file_selector`) opens a separate top-level window,
// which the compositor stacks *behind* the layer-shell panels — unusable. This
// component instead renders a themed modal into the settings overlay's root
// [Overlay] (the same mechanism the color picker uses in
// `overlay/settings/shell.dart`), so it always appears on top of the panel.
//
// It is deliberately general: [showFilePicker] takes a list of
// [FilePickerFilter]s and a multi-select flag, so any settings surface can reuse
// it, not just the wallpaper flow.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xdg_icons/xdg_icons.dart';

import 'package:graceful_shell/root_modal.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/overlay/file_picker_controller.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
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
/// clipped overlay can't cut it off — see the color picker in
/// `overlay/settings/shell.dart` for the same pattern.
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

String get _homeDir => Platform.environment['HOME'] ?? '/';

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
  final Set<String> _expanded = {};
  final Set<String> _selected = {};

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
  }

  void _selectDir(String path) {
    setState(() {
      _currentDir = path;
      _expanded.add(path);
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
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
                  final w = (constraints.maxWidth * 0.9).clamp(320.0, 760.0);
                  final h = (constraints.maxHeight * 0.9).clamp(320.0, 520.0);
                  return PopupBounceIn(
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme),
          Container(height: 1, color: theme.divider),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 220, child: _treePane(theme)),
                Container(width: 1, color: theme.divider),
                Expanded(child: _filePane(theme)),
              ],
            ),
          ),
          Container(height: 1, color: theme.divider),
          _footer(theme),
        ],
      ),
    );
  }

  Widget _header(ThemeConfig theme) {
    // Present the current path with the home prefix folded to `~`, the way most
    // file managers do.
    var shown = _currentDir;
    if (_homeDir != '/' && shown.startsWith(_homeDir)) {
      shown = '~${shown.substring(_homeDir.length)}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (widget.filters.length > 1)
            SettingsSegmented(
              options: [for (final f in widget.filters) f.label],
              value: _filter.label,
              onChanged: (label) => setState(() =>
                  _filterIndex = widget.filters.indexWhere((f) => f.label == label)),
            ),
          const SizedBox(width: 12),
          _HiddenToggle(
            value: _showHidden,
            onChanged: (v) => setState(() => _showHidden = v),
          ),
          const SizedBox(width: 4),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: 13,
            onTap: () => widget.onResult(null),
          ),
        ],
      ),
    );
  }

  Widget _treePane(ThemeConfig theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _filePane(ThemeConfig theme) {
    final entries = sortEntries(readDir(_currentDir, showHidden: _showHidden));
    // With allowDirectories the folders in this directory become selectable
    // tiles *as well as* tree rows. The type filter deliberately does not apply
    // to them — a folder has no extension to match.
    final files = <FileSystemEntity>[
      if (widget.allowDirectories) ...entries.whereType<Directory>(),
      ...entries.whereType<File>().where((f) => _filter.matches(f.path)),
    ];

    if (files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.allowDirectories
                ? 'Nothing to select in this folder.'
                : 'No matching files in this folder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final f in files)
            _FileTile(
              path: f.path,
              selected: _selected.contains(f.path),
              onTap: () => _toggleFile(f.path),
            ),
        ],
      ),
    );
  }

  Widget _footer(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Text(
            _selected.isEmpty
                ? (widget.allowDirectories
                    ? basenameOf(_currentDir)
                    : 'Nothing selected')
                : '${_selected.length} selected',
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          SettingsOptionButton(
            label: 'Cancel',
            selected: false,
            onTap: () => widget.onResult(null),
          ),
          const SizedBox(width: 8),
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
/// surface has none of — and could not usefully have, since it is on the
/// background layer and anything drawn there sits under every application
/// window. The root creates an overlay-layer window and renders this into it;
/// `FilePickerController` is the seam that asks for one.
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
      // picker has no text field today, but it does bind Escape, and a future
      // filter box would silently swallow Backspace without this.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 14,
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

/// A single row in the directory tree, plus (when expanded) its child rows.
///
/// The tree's expansion/selection state lives in [_FilePickerDialogState]; this
/// node reads it and rebuilds when the dialog does. Children are listed lazily —
/// only when the node is expanded.
///
/// The node is stateless and the hover highlight lives in [_TreeRow], so
/// hovering a row rebuilds *only that row* — it never re-runs this node's build,
/// which would otherwise re-list the directory ([subDirs]) and rebuild the whole
/// child subtree on every pointer move, and flicker.
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
          left: 8.0 + depth * 14,
          right: 8,
          top: 5,
          bottom: 5,
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(path),
              child: SizedBox(
                width: 16,
                child: FaIcon(
                  isExpanded
                      ? FontAwesomeIcons.chevronDown
                      : FontAwesomeIcons.chevronRight,
                  size: 9,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            XdgIcon(
              name: 'folder',
              size: 14,
              iconNotFoundBuilder: () => FaIcon(
                FontAwesomeIcons.solidFolder,
                size: 12,
                color: theme.accent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
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


/// A file entry in the right pane: an image thumbnail when the file is an image,
/// otherwise a type icon, with the name below and an accent check when selected.
class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isImage = isImagePath(path);

    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 88,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: isImage
                        ? Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            gaplessPlayback: true,
                            errorBuilder: (c, e, s) =>
                                _iconBox(theme),
                          )
                        : _iconBox(theme),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? theme.accent
                            : (hovered ? theme.surfaceHover : theme.divider),
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: theme.accent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const FaIcon(
                          FontAwesomeIcons.check,
                          size: 9,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              basenameOf(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(ThemeConfig theme) {
    return ColoredBox(
      color: theme.controlSurface,
      child: Center(
        child: FaIcon(
          iconForFile(path),
          size: 28,
          color: theme.popupForeground.withValues(alpha: 0.55),
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
