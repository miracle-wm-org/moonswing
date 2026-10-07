// The todo board: five columns of cards over a scrim, in its own full-screen
// layer-shell window on the output whose bar was clicked.
//
// It reads nothing itself. [TodoStore] owns the database, the history of moves
// and the day turning over; `todo_model.dart` owns every date rule, and
// [TodoBoardSearch] what the search field leaves showing. This file is the
// panel, the search field, the columns, the cards, drag and drop between them,
// a card's right-click menu, and the editor that creates and changes one. The
// backups card over it is `todo_backup_panel.dart`.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/app_info.dart' show openUriWithDefault;
import 'package:moonswing/desktop/desktop_menu.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_link_chip.dart';
import 'package:moonswing/github/github_link_store.dart';
import 'package:moonswing/github/github_links.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/overlay_search_field.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/todo/todo_backup_panel.dart';
import 'package:moonswing/todo/todo_caldav_sync.dart';
import 'package:moonswing/todo/todo_layout.dart';
import 'package:moonswing/todo/todo_links.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_search.dart';
import 'package:moonswing/todo/todo_standup_panel.dart';
import 'package:moonswing/todo/todo_store.dart';

/// How much of the output the board takes. Most of it: five columns of cards
/// want width, and the scrim left around the edge is what says it is an
/// overlay rather than an application window.
const double kTodoPanelWidthFraction = 0.94;
const double kTodoPanelHeightFraction = 0.9;

/// The gap between two cards, which is also where a drop indicator is drawn.
const double kTodoCardGap = 8;

/// The editor card's width.
const double kTodoEditorWidth = 540;

/// The search field's width in the header.
const double kTodoSearchWidth = 320;

/// The board's panel size for an overlay surface of [available] logical pixels.
Size todoPanelSize(Size available) => Size(
  available.width * kTodoPanelWidthFraction,
  available.height * kTodoPanelHeightFraction,
);

/// What the editor was opened for: an existing item, or a new one in a column.
@immutable
class _EditRequest {
  const _EditRequest.edit(String this.id) : column = null;
  const _EditRequest.create(TodoColumn this.column) : id = null;

  final String? id;
  final TodoColumn? column;
}

/// The todo board and its backdrop.
///
/// Follows the [FadeOverlayScaffold] close handshake: the owner flips
/// [closingNotifier], this plays its exit animation, then calls [onClosed].
class TodoOverlay extends StatefulWidget {
  const TodoOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    this.store,
    this.sync,
    this.onOpenAccounts,
    this.onOpenLink = _openLink,
    this.copy = copyTextToClipboard,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Defaults to the singleton; a widget test passes one over a temporary
  /// directory.
  final TodoStore? store;

  /// The task-list sync. Defaults to the singleton.
  final TodoCalDavSync? sync;

  /// Opens Settings › Accounts. Injected by tests; the default asks the root
  /// through [SettingsController].
  final VoidCallback? onOpenAccounts;

  /// What a click on a link in a card's title or body does with its address.
  /// The browser by default; a widget test records it instead.
  final ValueChanged<String> onOpenLink;

  static void _openLink(String url) => openUriWithDefault(url);

  /// How a card menu's copy copies; a widget test records instead of forking
  /// `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  @override
  State<TodoOverlay> createState() => _TodoOverlayState();
}

class _TodoOverlayState extends State<TodoOverlay> {
  late final TodoStore _store = widget.store ?? TodoStore.instance;
  late final TodoCalDavSync _sync = widget.sync ?? TodoCalDavSync.instance;

  @override
  void initState() {
    super.initState();
    // Opening the board is when somebody is about to read it: whatever
    // changed on the phone since the last poll is fetched now.
    _sync.syncIfStale();
  }

  void _openAccounts() {
    final open = widget.onOpenAccounts;
    if (open != null) {
      open();
    } else {
      SettingsController.instance.open(SettingsRoute.accounts);
    }
    _requestClose();
  }

  /// Whether the backups card is open. A notifier for [_editing]'s reason.
  final ValueNotifier<bool> _backups = ValueNotifier(false);

  /// Whether the standup card is open. A notifier for [_editing]'s reason.
  final ValueNotifier<bool> _standup = ValueNotifier(false);
  final FocusNode _focusNode = FocusNode(debugLabel: 'todo board');

  /// The search field's, owned here so the key handler can read and clear it.
  final TextEditingController _searchText = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'todo search');
  late final TodoBoardSearch _search = TodoBoardSearch(_store);

  /// What the board rebuilds on. Merged once, here: a merge built in `build`
  /// would re-subscribe on every rebuild.
  late final Listenable _board = Listenable.merge([_store, _search]);

  /// Which of Finished's and Abandoned's day groups are open.
  late final _DayFoldsNotifier _folds = _DayFoldsNotifier(_search);

  /// The open editor, or null. A notifier rather than state on this widget, so
  /// opening the editor rebuilds the editor layer and not five columns of
  /// cards.
  final ValueNotifier<_EditRequest?> _editing = ValueNotifier(null);

  /// The open card menu, or null. A notifier for [_editing]'s reason.
  final ValueNotifier<_CardMenuRequest?> _menu = ValueNotifier(null);

  /// The panel's layer stack, which a card menu's position is measured in.
  final GlobalKey _layersKey = GlobalKey(debugLabel: 'todo layers');

  /// Why the last copy from a card menu did not reach the clipboard, or null.
  final ValueNotifier<String?> _copyError = ValueNotifier(null);

  /// The panel lives in an [Overlay] of its own, for two things that insert
  /// into the nearest one: a dragged card's feedback, and the editor's
  /// dropdowns.
  late final OverlayEntry _panelEntry = OverlayEntry(
    builder: (context) => FadeOverlayScaffold(
      closing: widget.closingNotifier,
      onClosed: widget.onClosed,
      // A click on the scrim closes the board — it holds nothing unsaved —
      // but not while the editor is open, which does.
      onBackdropTap: () {
        if (_menu.value != null) {
          _menu.value = null;
        } else if (_editing.value == null &&
            !_backups.value &&
            !_standup.value) {
          _requestClose();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = todoPanelSize(constraints.biggest);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: _TodoPanel(
              store: _store,
              board: _board,
              search: _search,
              folds: _folds,
              searchField: _buildSearchField(context),
              editing: _editing,
              onEditorDone: _closeEditor,
              menu: _menu,
              layersKey: _layersKey,
              copyError: _copyError,
              onCopy: _copy,
              backups: _backups,
              standup: _standup,
              sync: _sync,
              onOpenAccounts: _openAccounts,
              onClose: _requestClose,
              onOpenLink: widget.onOpenLink,
            ),
          );
        },
      ),
    ),
  );

  void _requestClose() => widget.closingNotifier.value = true;

  /// Closes the editor and gives the keyboard back to the search field: the
  /// editor's title had it, and a focus left on nothing would leave Escape and
  /// Ctrl+F with no one to hear them.
  void _closeEditor() {
    _editing.value = null;
    _searchFocus.requestFocus();
  }

  /// Copies [text] from a card menu, saying so on the board if it could not.
  Future<void> _copy(String text) async {
    final result = await widget.copy(text);
    if (!mounted) return;
    _copyError.value = switch (result) {
      ClipboardResult.copied => null,
      ClipboardResult.unavailable =>
        'Install $kClipboardPackage to copy from a card.',
      ClipboardResult.failed => '$kClipboardCommand could not copy it.',
    };
  }

  Widget _buildSearchField(BuildContext context) => SizedBox(
    width: kTodoSearchWidth,
    child: OverlaySearchField(
      controller: _searchText,
      focusNode: _searchFocus,
      theme: ThemeScope.of(context),
      hint: 'Search todos',
      onChanged: (value) => _search.query = value,
    ),
  );

  void _clearSearch() {
    _searchText.clear();
    _search.clear();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchText.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchText.text.length,
    );
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        _menu.value == null &&
        _editing.value == null &&
        !_backups.value &&
        !_standup.value) {
      _focusSearch();
      return;
    }
    if (key != LogicalKeyboardKey.escape) return;
    // Escape backs out one layer at a time: a card menu, the editor, then the
    // search, then the board.
    if (_menu.value != null) {
      _menu.value = null;
    } else if (_editing.value != null) {
      _closeEditor();
    } else if (_backups.value) {
      _backups.value = false;
      _searchFocus.requestFocus();
    } else if (_standup.value) {
      _standup.value = false;
      _searchFocus.requestFocus();
    } else if (_searchText.text.isNotEmpty) {
      _clearSearch();
    } else {
      _requestClose();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchFocus.dispose();
    _searchText.dispose();
    _folds.dispose();
    _search.dispose();
    _editing.dispose();
    _menu.dispose();
    _copyError.dispose();
    _backups.dispose();
    _standup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      // No WidgetsApp above any shell window, so the editing keys a text field
      // needs are supplied here, as the settings overlay does.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: ShellFontSizes.body,
            color: theme.popupForeground,
          ),
          // Hears every key the fields inside let through. Not autofocused:
          // the search field is, so the board opens ready to be searched.
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _onKey,
            // Opaque popups, for the settings overlay's reason: the editor's
            // dropdowns float over dense text.
            child: OpaquePopupScope(
              child: Overlay(initialEntries: [_panelEntry]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The solid card: header, the five columns, and the editor over them.
class _TodoPanel extends StatelessWidget {
  const _TodoPanel({
    required this.store,
    required this.board,
    required this.search,
    required this.folds,
    required this.searchField,
    required this.editing,
    required this.onEditorDone,
    required this.menu,
    required this.layersKey,
    required this.copyError,
    required this.onCopy,
    required this.backups,
    required this.standup,
    required this.sync,
    required this.onOpenAccounts,
    required this.onClose,
    required this.onOpenLink,
  });

  final TodoStore store;
  final ValueNotifier<bool> backups;
  final ValueNotifier<bool> standup;
  final TodoCalDavSync sync;
  final VoidCallback onOpenAccounts;

  /// [store] and [search] together.
  final Listenable board;
  final TodoBoardSearch search;
  final _DayFoldsNotifier folds;

  /// Built by the overlay, which owns its controller and focus; handed in
  /// unchanged so a board rebuild does not rebuild the field.
  final Widget searchField;
  final ValueNotifier<_EditRequest?> editing;
  final VoidCallback onEditorDone;
  final ValueNotifier<_CardMenuRequest?> menu;

  /// On the [Stack] the editor, the other cards and the menu are layered in.
  final GlobalKey layersKey;
  final ValueNotifier<String?> copyError;
  final ValueChanged<String> onCopy;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        // Always opaque, whatever alpha the theme gives popups: this is a
        // workspace of small text, like the settings panel.
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accent, width: 1.5),
      ),
      // The card swallows its own clicks, so a click between two columns is
      // not a click on the scrim.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            key: layersKey,
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: board,
                  builder: (context, _) => _buildBoard(context, theme),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<_EditRequest?>(
                  valueListenable: editing,
                  builder: (context, request, _) => request == null
                      ? const SizedBox.shrink()
                      : _EditorLayer(
                          // Keyed on the request, so opening a different item
                          // seeds a fresh set of fields.
                          key: ObjectKey(request),
                          store: store,
                          request: request,
                          onDone: onEditorDone,
                        ),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: backups,
                  builder: (context, open, _) => !open
                      ? const SizedBox.shrink()
                      : TodoBackupLayer(
                          store: store,
                          sync: sync,
                          onDone: () => backups.value = false,
                          onOpenAccounts: onOpenAccounts,
                        ),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: standup,
                  builder: (context, open, _) => !open
                      ? const SizedBox.shrink()
                      : TodoStandupLayer(
                          store: store,
                          onDone: () => standup.value = false,
                          onOpenLink: onOpenLink,
                        ),
                ),
              ),
              // Last, so a menu opened over a card is over everything.
              Positioned.fill(
                child: ValueListenableBuilder<_CardMenuRequest?>(
                  valueListenable: menu,
                  builder: (context, request, _) => request == null
                      ? const SizedBox.shrink()
                      : _CardMenuLayer(
                          request: request,
                          onCopy: (text) {
                            menu.value = null;
                            onCopy(text);
                          },
                          onDismiss: () => menu.value = null,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens [item]'s menu at [at], a global position, measured into the layer
  /// the menu is drawn in.
  void _openMenu(TodoItem item, Offset at) {
    final layers = layersKey.currentContext?.findRenderObject();
    menu.value = _CardMenuRequest(
      item,
      layers is RenderBox ? layers.globalToLocal(at) : at,
    );
  }

  Widget _buildBoard(BuildContext context, ThemeConfig theme) {
    final loadError = store.loadError;
    final writeError = store.writeError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          onClose: onClose,
          onBackups: () => backups.value = true,
          // Disabled while the board did not read: it has nothing true to say.
          onStandup: store.editable ? () => standup.value = true : null,
          search: search,
          searchField: searchField,
        ),
        Container(height: 1, color: theme.divider),
        ValueListenableBuilder<String?>(
          valueListenable: copyError,
          builder: (context, error, _) => error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SettingsBanner(
                    title: 'Nothing was copied',
                    message: error,
                    action: SettingsActionButton(
                      label: 'OK',
                      compact: true,
                      onTap: () => copyError.value = null,
                    ),
                  ),
                ),
        ),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SettingsBanner(
              title: 'The todo list could not be read',
              message:
                  '$loadError\nNothing will be saved over it until it reads '
                  'cleanly. Its backup file is '
                  '${displayPath(store.backupPath)}, and Backups can '
                  'restore from it.',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsActionButton(
                    label: 'Backups…',
                    compact: true,
                    onTap: () => backups.value = true,
                  ),
                  const SizedBox(width: 8),
                  SettingsActionButton(
                    label: 'Retry',
                    compact: true,
                    onTap: store.retry,
                  ),
                ],
              ),
            ),
          )
        else if (store.recoveryNotice case final notice?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SettingsBanner(
              title: 'The board was restored from its backup',
              message:
                  '$notice\nAnything changed after that backup was written is '
                  'not on the board.',
              action: SettingsActionButton(
                label: 'OK',
                compact: true,
                onTap: store.dismissRecoveryNotice,
              ),
            ),
          )
        else if (writeError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SettingsBanner(
              title: 'Changes are not being saved',
              message: writeError,
              action: SettingsActionButton(
                label: 'Retry',
                compact: true,
                onTap: store.flush,
              ),
            ),
          ),
        Expanded(
          child: !store.loaded
              ? const Center(child: LoadingIndicator(size: 24))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final column in TodoColumn.values) ...[
                        if (column != TodoColumn.values.first)
                          const SizedBox(width: 12),
                        Expanded(
                          child: _ColumnView(
                            column: column,
                            items: [
                              for (final item in store.itemsIn(column))
                                if (search.shows(item.id)) item,
                            ],
                            filtered: search.active,
                            terms: search.terms,
                            folds: folds,
                            store: store,
                            onEdit: (id) =>
                                editing.value = _EditRequest.edit(id),
                            onMenu: _openMenu,
                            onOpenLink: onOpenLink,
                            onAdd: () =>
                                editing.value = _EditRequest.create(column),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        Container(height: 1, color: theme.divider),
        TodoBackupFooter(
          store: store,
          sync: sync,
          onOpen: () => backups.value = true,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onClose,
    required this.onBackups,
    required this.onStandup,
    required this.search,
    required this.searchField,
  });

  final VoidCallback onClose;
  final VoidCallback onBackups;
  final VoidCallback? onStandup;
  final TodoBoardSearch search;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.listCheck,
            size: ShellFontSizes.title,
            color: theme.accentText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Todo',
              style: TextStyle(
                fontSize: ShellFontSizes.heading,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
          ),
          if (search.active) ...[
            Text(
              _describeMatches(search.matches?.length ?? 0),
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
          ],
          searchField,
          const SizedBox(width: 8),
          if (onStandup case final onStandup?) ...[
            _HeaderButton(
              tooltip:
                  'Standup summaries: what was finished, started and still to '
                  'do since the last one',
              onTap: onStandup,
              builder: (color) => FaIcon(
                FontAwesomeIcons.bullhorn,
                size: ShellFontSizes.body,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
          ],
          _HeaderButton(
            tooltip: 'Backups',
            onTap: onBackups,
            builder: (color) => FaIcon(
              FontAwesomeIcons.cloudArrowUp,
              size: ShellFontSizes.body,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            tooltip: 'Close',
            onTap: onClose,
            builder: (color) => Text(
              '✕',
              style: TextStyle(fontSize: ShellFontSizes.title, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the header's icon-only buttons, named on hover.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.onTap,
    required this.builder,
  });

  final String tooltip;
  final VoidCallback onTap;

  /// The glyph, in the colour the hover state gives it.
  final Widget Function(Color color) builder;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsTooltip(
      message: tooltip,
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ShellRadii.control),
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
          ),
          child: Center(
            child: builder(
              theme.popupForeground.withValues(alpha: hovered ? 0.9 : 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

String _describeMatches(int count) => switch (count) {
  0 => 'No matches',
  1 => '1 match',
  _ => '$count matches',
};

/// One column: its heading, its add button, and its cards — and the drop
/// target for the space below the last card.
class _ColumnView extends StatelessWidget {
  const _ColumnView({
    required this.column,
    required this.items,
    required this.filtered,
    required this.terms,
    required this.folds,
    required this.store,
    required this.onEdit,
    required this.onMenu,
    required this.onOpenLink,
    required this.onAdd,
  });

  final TodoColumn column;

  /// The cards shown: every card in the column, or those the search matched,
  /// in the store's order. [layoutColumn] decides how they are drawn.
  final List<TodoItem> items;

  /// Whether a search is hiding some of the column.
  final bool filtered;

  /// What to highlight on each card.
  final List<String> terms;
  final _DayFoldsNotifier folds;
  final TodoStore store;
  final ValueChanged<String> onEdit;
  final _CardMenuCallback onMenu;
  final ValueChanged<String> onOpenLink;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final editable = store.editable;
    // The column itself takes whatever lands below its last card (or on an
    // empty column), and puts it at the bottom. A card's own target sits
    // deeper in the tree and is asked first, so this only sees the gaps.
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => editable,
      onAcceptWithDetails: (details) => store.move(details.data, column),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: hovering
                ? theme.accent.withValues(alpha: 0.10)
                : theme.controlSurface.atMostAlpha(0.5),
            borderRadius: BorderRadius.circular(ShellRadii.card),
            border: Border.all(color: hovering ? theme.accent : theme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.label,
                          fontWeight: FontWeight.w600,
                          color: theme.popupForeground,
                        ),
                      ),
                    ),
                    Text(
                      '${items.length}',
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        color: theme.popupForeground.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // An add button goes at the top right of the collection
                    // it adds to.
                    SettingsIconButton(
                      icon: FontAwesomeIcons.plus,
                      enabled: editable,
                      onTap: onAdd,
                      tooltip: 'Add a card to ${column.label}',
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: theme.divider),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          filtered
                              ? 'No matches'
                              : editable
                              ? 'Drop a card here'
                              : '',
                          style: TextStyle(
                            fontSize: ShellFontSizes.secondary,
                            color: theme.popupForeground.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      )
                    : _buildList(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final layout = layoutColumn(column, items, store.now);
    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        // Only a column with day groups listens: folding one rebuilds that
        // column's rows, not the board.
        listenable: layout.days.isEmpty ? _never : folds,
        builder: (context, _) {
          final rows = <Object>[
            ...layout.loose,
            for (final group in layout.days) ...[
              group,
              if (folds.isOpen(column, group.day, searching: filtered))
                ...group.items,
            ],
          ];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              8,
              kTodoCardGap,
              8,
              // Room under the last card to drop onto.
              48,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              final TodoDayGroup group => Padding(
                key: ValueKey(group.day),
                padding: const EdgeInsets.only(bottom: kTodoCardGap),
                child: _DayHeading(
                  day: group.day,
                  today: store.now,
                  count: group.items.length,
                  open: folds.isOpen(column, group.day, searching: filtered),
                  onTap: () =>
                      folds.toggle(column, group.day, searching: filtered),
                ),
              ),
              final TodoItem item => Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: kTodoCardGap),
                child: _DraggableCard(
                  item: item,
                  terms: terms,
                  width: constraints.maxWidth - 16,
                  store: store,
                  onEdit: onEdit,
                  onMenu: onMenu,
                  onOpenLink: onOpenLink,
                ),
              ),
              _ => const SizedBox.shrink(),
            },
          );
        },
      ),
    );
  }
}

/// A listenable that never fires, for a column with nothing to fold.
const Listenable _never = _Never();

class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// [TodoDayFolds] for the board: notifies when a group is flipped, and forgets
/// what was flipped by hand whenever the search's words change.
class _DayFoldsNotifier extends ChangeNotifier {
  _DayFoldsNotifier(this._search) : _terms = _search.terms {
    _search.addListener(_onSearch);
  }

  final TodoBoardSearch _search;
  final TodoDayFolds _folds = TodoDayFolds();
  List<String> _terms;

  bool isOpen(TodoColumn column, DateTime day, {required bool searching}) =>
      _folds.isOpen(column, day, searching: searching);

  void toggle(TodoColumn column, DateTime day, {required bool searching}) {
    _folds.toggle(column, day, searching: searching);
    notifyListeners();
  }

  /// The search notifies when its words change and when a store edit moves
  /// its matches; only the first is a new search.
  void _onSearch() {
    final terms = _search.terms;
    if (listEquals(terms, _terms)) return;
    _terms = terms;
    if (_folds.reset()) notifyListeners();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    super.dispose();
  }
}

/// The heading of one day's cards in Finished or Abandoned: the day, how many
/// cards it holds, and a chevron saying whether they are showing. A click
/// folds or unfolds it.
class _DayHeading extends StatelessWidget {
  const _DayHeading({
    required this.day,
    required this.today,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final dim = theme.popupForeground.withValues(alpha: 0.6);
    // Its own layer, for a card's reason: the hover tint repaints the heading.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          constraints: const BoxConstraints(
            minHeight: ShellSizes.minTapTarget + 4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: FaIcon(
                  open
                      ? FontAwesomeIcons.chevronDown
                      : FontAwesomeIcons.chevronRight,
                  size: ShellFontSizes.caption,
                  color: dim,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  describeDueDate(day, today),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontWeight: FontWeight.w600,
                    color: theme.popupForeground.withValues(
                      alpha: hovered ? 0.9 : 0.75,
                    ),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: ShellFontSizes.caption, color: dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card that can be picked up, and that takes a drop *above* itself.
class _DraggableCard extends StatelessWidget {
  const _DraggableCard({
    required this.item,
    required this.terms,
    required this.width,
    required this.store,
    required this.onEdit,
    required this.onMenu,
    required this.onOpenLink,
  });

  final TodoItem item;
  final List<String> terms;
  final double width;
  final TodoStore store;
  final ValueChanged<String> onEdit;
  final _CardMenuCallback onMenu;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final face = _CardFace(
      item: item,
      today: store.now,
      terms: terms,
      onOpenLink: onOpenLink,
    );
    final stripe = calendarCardColor(item, theme);
    final card = HoverRegion(
      onTap: () => onEdit(item.id),
      onSecondaryTapDown: (details) => onMenu(item, details.globalPosition),
      builder: (context, hovered) =>
          _CardChrome(hovered: hovered, stripe: stripe, child: face),
    );
    if (!store.editable) return RepaintBoundary(child: card);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != item.id,
      onAcceptWithDetails: (details) =>
          store.move(details.data, item.column, beforeId: item.id),
      builder: (context, candidates, _) => Stack(
        // Passthrough, so the card keeps the column's full width: a loose
        // Stack would shrink it to its text.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          // Its own layer: a card's hover tint repaints the card, not the
          // column around it.
          RepaintBoundary(
            child: Draggable<String>(
              data: item.id,
              // The feedback floats in the board's own Overlay, outside the
              // column's constraints, so it is given the column's width.
              feedback: SizedBox(
                width: width,
                child: _CardChrome(
                  hovered: true,
                  lifted: true,
                  stripe: stripe,
                  child: face,
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _CardChrome(hovered: false, stripe: stripe, child: face),
              ),
              child: card,
            ),
          ),
          // The drop indicator is drawn in the gap above the card rather than
          // inserted into the column, so the cards do not jump out from under
          // the pointer as it arrives.
          if (candidates.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: -(kTodoCardGap / 2) - 1.5,
              height: 3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The colour a card the calendar sync made is marked in: its calendar's, else
/// the theme's accent, the way the calendar overlay draws the same event. Null
/// for a card the user made.
@visibleForTesting
Color? calendarCardColor(TodoItem item, ThemeConfig theme) {
  final external = item.external;
  if (external == null) return null;
  final hex = external.color;
  return (hex == null ? null : parseHexColor(hex)) ?? theme.accent;
}

/// The width of the band down a calendar card's left edge.
const double _kStripeWidth = 4;

class _CardChrome extends StatelessWidget {
  const _CardChrome({
    required this.hovered,
    required this.child,
    this.lifted = false,
    this.stripe,
  });

  final bool hovered;
  final bool lifted;

  /// The band down the left edge that says where the card came from, or
  /// null for a card the user made.
  final Color? stripe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    const padding = EdgeInsets.fromLTRB(10, 8, 10, 8);
    final stripe = this.stripe;
    return Container(
      padding: stripe == null
          ? padding
          : padding.copyWith(left: padding.left + _kStripeWidth),
      decoration: BoxDecoration(
        color: hovered
            ? Color.alphaBlend(
                theme.surfaceHover.atMostAlpha(0.5),
                opaquePopupFill(theme),
              )
            : opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: hovered ? theme.accent : theme.divider),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: theme.popupShadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      // Painted as a decoration rather than laid out as a child, so the card's
      // height is still its text's alone and the band needs no intrinsic pass.
      foregroundDecoration: stripe == null
          ? null
          : _StripeDecoration(color: stripe, width: _kStripeWidth),
      child: child,
    );
  }
}

/// A band of [color] [width] wide down the left edge of a card, inside its
/// one-pixel border and following its rounded corners.
class _StripeDecoration extends Decoration {
  const _StripeDecoration({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      false;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _StripePainter(color, width);

  @override
  bool operator ==(Object other) =>
      other is _StripeDecoration &&
      other.color == color &&
      other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

class _StripePainter extends BoxPainter {
  _StripePainter(this.color, this.width);

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    // Inside the 1px border, so the inner radius is one less than the card's.
    const inner = Radius.circular(ShellRadii.control - 1);
    final rect = Rect.fromLTWH(
      offset.dx + 1,
      offset.dy + 1,
      width,
      size.height - 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topLeft: inner, bottomLeft: inner),
      Paint()..color = color,
    );
  }
}

/// What a card shows: the title, the start of the body, and a line of facts —
/// when it is due, how it repeats, and when it arrived in this column.
///
/// A web address in the title or body is a link: clicking it opens the address
/// and not the card, because the text's recognizer sits deeper than the card's
/// and so wins the tap. A link to a GitHub issue or pull request is drawn as a
/// chip carrying its title and state instead, while there is a GitHub account
/// to read it as ([GithubLinkChip]); the card then listens to
/// [GithubLinkStore] for the account coming and going, and nothing else.
class _CardFace extends StatefulWidget {
  const _CardFace({
    required this.item,
    required this.today,
    required this.onOpenLink,
    this.terms = const [],
  });

  final TodoItem item;
  final DateTime today;
  final ValueChanged<String> onOpenLink;

  /// What the search matched, drawn highlighted.
  final List<String> terms;

  @override
  State<_CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<_CardFace> {
  /// One recognizer per address on the card, kept across builds and disposed
  /// once the address is gone, since a [TextSpan] does not own its recognizer.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  TapGestureRecognizer _recognizerFor(TodoLink link) =>
      _recognizers.putIfAbsent(
        link.url,
        () => TapGestureRecognizer()..onTap = () => widget.onOpenLink(link.url),
      );

  /// Disposes the recognizers of addresses no longer in [links].
  void _forgetAllBut(Iterable<TodoLink> links) {
    final keep = {for (final link in links) link.url};
    _recognizers.removeWhere((url, recognizer) {
      if (keep.contains(url)) return false;
      recognizer.dispose();
      return true;
    });
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title.trim();
    final body = widget.item.body.trim();
    final titleLinks = findLinks(title);
    final bodyLinks = findLinks(body);
    _forgetAllBut([...titleLinks, ...bodyLinks]);
    final refs = <String, GithubRef>{
      for (final link in [...titleLinks, ...bodyLinks])
        link.url: ?parseGithubRef(link.url),
    };
    if (refs.isEmpty) {
      return _face(context, title, body, titleLinks, bodyLinks, refs, null);
    }
    final githubLinks = AccountsScope.githubLinksOf(context);
    return ListenableBuilder(
      listenable: githubLinks,
      builder: (context, _) =>
          _face(context, title, body, titleLinks, bodyLinks, refs, githubLinks),
    );
  }

  Widget _face(
    BuildContext context,
    String title,
    String body,
    List<TodoLink> titleLinks,
    List<TodoLink> bodyLinks,
    Map<String, GithubRef> refs,
    GithubLinkStore? githubLinks,
  ) {
    final item = widget.item;
    final terms = widget.terms;
    final theme = ThemeScope.of(context);
    final dim = theme.popupForeground.withValues(alpha: 0.6);
    final due = item.due;
    final recurrence = item.recurrence;
    final hit = TextStyle(
      backgroundColor: theme.accent.withValues(alpha: 0.35),
      color: theme.popupForeground,
    );
    final link = TextStyle(
      color: theme.accent,
      decoration: TextDecoration.underline,
      decorationColor: theme.accent,
    );
    final chips = githubLinks != null && githubLinks.enabled;
    List<InlineSpan> spans(String text, List<TodoLink> links, double size) =>
        highlightMatchesWithChips(
          text,
          terms,
          hit: hit,
          links: links,
          link: link,
          recognizerFor: _recognizerFor,
          chipFor: (link, matched) {
            final ref = refs[link.url];
            if (!chips || ref == null) return null;
            return githubLinkChipSpan(
              GithubLinkChip(
                store: githubLinks,
                ref: ref,
                highlighted: matched,
                fontSize: size,
                onOpen: () => widget.onOpenLink(link.url),
              ),
            );
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: title.isEmpty
                ? [const TextSpan(text: 'Untitled')]
                : spans(title, titleLinks, ShellFontSizes.body),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            fontWeight: FontWeight.w600,
            color: title.isEmpty ? dim : theme.popupForeground,
          ),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: spans(body, bodyLinks, ShellFontSizes.secondary),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: ShellFontSizes.secondary, color: dim),
          ),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (due != null)
              _DueChip(item: item, due: due, today: widget.today),
            if (recurrence != null)
              _Fact(
                icon: FontAwesomeIcons.repeat,
                label: recurrence.describe(),
              ),
            if (item.external case final e?)
              _Fact(
                icon: FontAwesomeIcons.calendar,
                label: e.calendar ?? 'Calendar',
                iconColor: calendarCardColor(item, theme),
              ),
            if (item.external?.link case final join? when item.column.isOpen)
              _JoinChip(onTap: () => widget.onOpenLink(join)),
            _Fact(
              icon: FontAwesomeIcons.clock,
              label: formatMoment(item.movedAt),
            ),
          ],
        ),
      ],
    );
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({required this.item, required this.due, required this.today});

  final TodoItem item;
  final DateTime due;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final day = dateOnly(today);
    final open = item.column.isOpen;
    final Color? color;
    if (open && due.isBefore(day)) {
      color = kErrorColor;
    } else if (open && due == day) {
      color = theme.accentText;
    } else {
      color = null;
    }
    return _Fact(
      icon: FontAwesomeIcons.calendarDay,
      label: describeDueDate(due, today),
      color: color,
    );
  }
}

/// A calendar card's way into the meeting: the link is in the body too, but a
/// meeting about to start wants a target bigger than a line of underlined text.
class _JoinChip extends StatelessWidget {
  const _JoinChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final chip = _Fact(
      icon: FontAwesomeIcons.video,
      label: 'Join',
      color: theme.accentText,
    );
    return SettingsTooltip(
      message: 'Join the meeting',
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          constraints: const BoxConstraints(minHeight: ShellSizes.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hovered
                ? theme.surfaceHover
                : theme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          alignment: Alignment.center,
          child: chip,
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    this.color,
    this.iconColor,
  });

  final FaIconData icon;
  final String label;
  final Color? color;

  /// The icon's own colour, where it differs from the label's.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final tint = color ?? theme.popupForeground.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(
          icon,
          size: ShellFontSizes.caption - 1,
          color: iconColor ?? tint,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: ShellFontSizes.caption, color: tint),
        ),
      ],
    );
  }
}

/// A right click on a card: the card as it was clicked, and where.
@immutable
class _CardMenuRequest {
  const _CardMenuRequest(this.item, this.at);

  final TodoItem item;

  /// The pointer, in the coordinates of the layer the menu is drawn in.
  final Offset at;
}

typedef _CardMenuCallback = void Function(TodoItem item, Offset at);

/// A card's right-click menu, opened at the pointer over a barrier covering
/// the board: a click anywhere else, a right click included, closes it.
///
/// Drawn in the board's own window rather than as a popup surface: the board
/// spans the output, so there is no outside for a menu to need to reach.
class _CardMenuLayer extends StatelessWidget {
  const _CardMenuLayer({
    required this.request,
    required this.onCopy,
    required this.onDismiss,
  });

  final _CardMenuRequest request;
  final ValueChanged<String> onCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = request.item;
    final title = item.title.trim();
    final body = item.body.trim();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTapDown: (_) => onDismiss(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _AtPointerLayout(request.at),
            // Absorbs clicks on the card's own chrome, which would otherwise
            // fall through to the barrier.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: DesktopMenuCard(
                entries: [
                  DesktopMenuEntry(
                    label: 'Copy title',
                    icon: FontAwesomeIcons.copy,
                    enabled: title.isNotEmpty,
                    onTap: () => onCopy(title),
                  ),
                  DesktopMenuEntry(
                    label: 'Copy description',
                    icon: FontAwesomeIcons.alignLeft,
                    enabled: body.isNotEmpty,
                    onTap: () => onCopy(body),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Puts the menu's top-left corner at the pointer, slid back inside the board
/// where it would hang off its right or bottom edge.
class _AtPointerLayout extends SingleChildLayoutDelegate {
  const _AtPointerLayout(this.at);

  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    at.dx.clamp(0, (size.width - childSize.width).clamp(0, double.infinity)),
    at.dy.clamp(0, (size.height - childSize.height).clamp(0, double.infinity)),
  );

  @override
  bool shouldRelayout(_AtPointerLayout oldDelegate) => oldDelegate.at != at;
}

const List<String> _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `24 Sep 2026, 14:02` — when a card was moved.
String formatMoment(DateTime at) =>
    '${at.day} ${_kMonths[at.month - 1]} ${at.year}, '
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// "Today", "Tomorrow", "Yesterday", or `24 Sep 2026`.
String describeDueDate(DateTime due, DateTime today) {
  final day = dateOnly(today);
  if (due == day) return 'Today';
  if (due == addDays(day, 1)) return 'Tomorrow';
  if (due == addDays(day, -1)) return 'Yesterday';
  return '${due.day} ${_kMonths[due.month - 1]} ${due.year}';
}

/// The editor, over a scrim that covers the board.
class _EditorLayer extends StatelessWidget {
  const _EditorLayer({
    super.key,
    required this.store,
    required this.request,
    required this.onDone,
  });

  final TodoStore store;
  final _EditRequest request;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final id = request.id;
    final existing = id == null ? null : store.item(id);
    // The item went away under the editor (deleted from elsewhere, or a retry
    // re-read the file without it): there is nothing left to edit.
    if (id != null && existing == null) return const SizedBox.shrink();
    return GestureDetector(
      // Absorbs clicks meant for the board underneath; deliberately not a
      // dismiss, because the editor holds a draft.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: theme.scrim,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kTodoEditorWidth.clamp(0, constraints.maxWidth - 32),
                maxHeight: (constraints.maxHeight - 32).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: _TodoEditor(
                store: store,
                existing: existing,
                column: existing?.column ?? request.column!,
                onDone: onDone,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The form behind a card: title, body, column, due date and repetition, and
/// the card's history of moves. Nothing is written until Save.
class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.store,
    required this.existing,
    required this.column,
    required this.onDone,
  });

  final TodoStore store;
  final TodoItem? existing;
  final TodoColumn column;
  final VoidCallback onDone;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.existing?.body ?? '',
  );
  late final TextEditingController _due = TextEditingController(
    text: switch (widget.existing?.due) {
      final due? => formatDate(due),
      null => '',
    },
  );
  late final TextEditingController _every = TextEditingController(
    text: '${widget.existing?.recurrence?.every ?? 1}',
  );
  late final TextEditingController _start = TextEditingController(
    text: formatDate(
      widget.existing?.recurrence?.start ?? dateOnly(widget.store.now),
    ),
  );

  /// The title's, focused as the editor opens. Asked for explicitly, because
  /// `autofocus` only takes focus in a scope where nothing has it, and the
  /// board's search field already does.
  final FocusNode _titleFocus = FocusNode(debugLabel: 'todo title');
  late TodoColumn _column = widget.column;
  late bool _repeats = widget.existing?.recurrence != null;
  late RecurrenceUnit _unit =
      widget.existing?.recurrence?.unit ?? RecurrenceUnit.weeks;

  @override
  void initState() {
    super.initState();
    // Every field the rest of the form reads back: the quick-pick chips light
    // off the due date, the Save button and the next-copy line off all three.
    for (final controller in [_due, _every, _start]) {
      controller.addListener(_onDraftChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _due, _every, _start]) {
      c.dispose();
    }
    _titleFocus.dispose();
    super.dispose();
  }

  /// The draft as the store would take it, or why it cannot be taken.
  ({String? error, DateTime? due, TodoRecurrence? recurrence}) _validate() {
    DateTime? due;
    if (_due.text.trim().isNotEmpty) {
      due = parseDate(_due.text);
      if (due == null) {
        return (
          error: 'The due date is not a date. Write it as YYYY-MM-DD.',
          due: null,
          recurrence: null,
        );
      }
    }
    if (!_repeats) return (error: null, due: due, recurrence: null);
    final every = int.tryParse(_every.text.trim());
    if (every == null || every < 1 || every > kMaxRecurrenceInterval) {
      return (
        error: 'Repeat every 1 to $kMaxRecurrenceInterval ${_unit.plural}.',
        due: due,
        recurrence: null,
      );
    }
    final start = parseDate(_start.text);
    if (start == null) {
      return (
        error:
            'The first scheduled day is not a date. Write it as '
            'YYYY-MM-DD.',
        due: due,
        recurrence: null,
      );
    }
    final previous = widget.existing?.recurrence;
    final today = dateOnly(widget.store.now);
    final unchanged =
        previous != null &&
        previous.every == every &&
        previous.unit == _unit &&
        previous.start == start;
    return (
      error: null,
      due: due,
      // An untouched rule keeps its record of the last copy. A new or changed
      // one counts from today: the card being edited stands for today, so the
      // first copy is the next scheduled day after it.
      recurrence: TodoRecurrence(
        every: every,
        unit: _unit,
        start: start,
        since: unchanged ? previous.since : today,
      ),
    );
  }

  void _save() {
    final draft = _validate();
    if (draft.error != null) return;
    final existing = widget.existing;
    if (existing == null) {
      widget.store.add(
        _column,
        title: _title.text.trim(),
        body: _body.text.trimRight(),
        due: draft.due,
        recurrence: draft.recurrence,
      );
    } else {
      widget.store.update(
        existing.id,
        title: _title.text.trim(),
        body: _body.text.trimRight(),
        column: _column,
        due: draft.due,
        recurrence: draft.recurrence,
      );
    }
    widget.onDone();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final title = existing.title.trim();
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Delete this item?',
      message:
          '${title.isEmpty ? 'This item' : '“$title”'} and its history will be '
          'gone for good. Moving it to Abandoned keeps both.',
      warning: existing.recurrence == null
          ? null
          : 'It is the item that repeats, so no more copies of it will be '
                'made.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    widget.store.delete(existing.id);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final existing = widget.existing;
    final draft = _validate();
    final today = dateOnly(widget.store.now);
    final parsedDue = parseDate(_due.text);
    return Container(
      decoration: BoxDecoration(
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.accent),
        boxShadow: [BoxShadow(color: theme.popupShadowColor, blurRadius: 24)],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              existing == null ? 'New item' : 'Edit item',
              style: TextStyle(
                fontSize: ShellFontSizes.title,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
            const SizedBox(height: 14),
            const _Label('Title'),
            SettingsTextField(
              controller: _title,
              focusNode: _titleFocus,
              hint: 'What needs doing',
              onChanged: (_) {},
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            const _Label('Details'),
            SettingsTextField(
              controller: _body,
              hint: 'Notes, links, anything else',
              maxLines: 8,
              minLines: 4,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            const _Label('Column'),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 200,
                child: SettingsDropdown<TodoColumn>(
                  items: [
                    for (final column in TodoColumn.values)
                      SettingsDropdownItem(value: column, label: column.label),
                  ],
                  selected: _column,
                  onSelected: (column) => setState(() => _column = column),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _Label('Due'),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: SettingsTextField(
                    controller: _due,
                    hint: 'YYYY-MM-DD',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, day) in [
                        ('Today', today),
                        ('Tomorrow', addDays(today, 1)),
                        ('Next week', addDays(today, 7)),
                      ])
                        SettingsOptionButton(
                          label: label,
                          selected: parsedDue == day,
                          onTap: () => _due.text = formatDate(day),
                        ),
                      SettingsOptionButton(
                        label: 'None',
                        selected: _due.text.trim().isEmpty,
                        onTap: () => _due.text = '',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: _Label('Repeats', bottom: 0)),
                SettingsToggle(
                  value: _repeats,
                  onChanged: (value) => setState(() => _repeats = value),
                ),
              ],
            ),
            if (_repeats) ...[
              const SizedBox(height: 10),
              // A Wrap, so a narrow editor puts the start date on a line of
              // its own rather than overflowing.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Every'),
                  SizedBox(
                    width: 64,
                    child: SettingsTextField(
                      controller: _every,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (_) {},
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: SettingsDropdown<RecurrenceUnit>(
                      items: [
                        for (final unit in RecurrenceUnit.values)
                          SettingsDropdownItem(value: unit, label: unit.plural),
                      ],
                      selected: _unit,
                      onSelected: (unit) => setState(() => _unit = unit),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('starting'),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: SettingsTextField(
                          controller: _start,
                          hint: 'YYYY-MM-DD',
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                switch (draft.recurrence) {
                  final rule? =>
                    'A copy of this item is added to Todo on each scheduled '
                        'day, due that day. The next one is on '
                        '${describeDueDate(rule.next, today)}.',
                  null => '',
                },
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: theme.popupForeground.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (existing != null) ...[
              const SizedBox(height: 16),
              const _Label('History'),
              for (final move in existing.history.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          move.from == null
                              ? 'Created in ${move.to.label}'
                              : '${move.from!.label} → ${move.to.label}',
                          style: const TextStyle(
                            fontSize: ShellFontSizes.secondary,
                          ),
                        ),
                      ),
                      Text(
                        formatMoment(move.at),
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (draft.error != null) ...[
              const SizedBox(height: 12),
              Text(
                draft.error!,
                style: const TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: kErrorColor,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (existing != null)
                  SizedBox(
                    width: 90,
                    child: SettingsActionButton(
                      label: 'Delete',
                      onTap: _delete,
                    ),
                  ),
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
                    enabled: draft.error == null && widget.store.editable,
                    onTap: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.bottom = 6});

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
