// The todo board: five columns of cards over a scrim, in its own full-screen
// layer-shell window on the output whose bar was clicked.
//
// It reads nothing itself. [TodoStore] owns the file, the history of moves and
// the day turning over; `todo_model.dart` owns every date rule. This file is the
// panel, the columns, the cards, drag and drop between them, and the editor
// that creates and changes one.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/todo/todo_model.dart';
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
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// Defaults to the singleton; a widget test passes one over a temporary
  /// directory.
  final TodoStore? store;

  @override
  State<TodoOverlay> createState() => _TodoOverlayState();
}

class _TodoOverlayState extends State<TodoOverlay> {
  late final TodoStore _store = widget.store ?? TodoStore.instance;
  final FocusNode _focusNode = FocusNode(debugLabel: 'todo board');

  /// The open editor, or null. A notifier rather than state on this widget, so
  /// opening the editor rebuilds the editor layer and not five columns of
  /// cards.
  final ValueNotifier<_EditRequest?> _editing = ValueNotifier(null);

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
        if (_editing.value == null) _requestClose();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = todoPanelSize(constraints.biggest);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: _TodoPanel(
              store: _store,
              editing: _editing,
              onClose: _requestClose,
            ),
          );
        },
      ),
    ),
  );

  void _requestClose() => widget.closingNotifier.value = true;

  @override
  void dispose() {
    _focusNode.dispose();
    _editing.dispose();
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
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is! KeyDownEvent ||
                  event.logicalKey != LogicalKeyboardKey.escape) {
                return;
              }
              // Escape backs out one layer at a time: the editor first, then
              // the board.
              if (_editing.value != null) {
                _editing.value = null;
                _focusNode.requestFocus();
              } else {
                _requestClose();
              }
            },
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
    required this.editing,
    required this.onClose,
  });

  final TodoStore store;
  final ValueNotifier<_EditRequest?> editing;
  final VoidCallback onClose;

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
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: store,
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
                          onDone: () => editing.value = null,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context, ThemeConfig theme) {
    final loadError = store.loadError;
    final writeError = store.writeError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onClose: onClose),
        Container(height: 1, color: theme.divider),
        if (loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SettingsBanner(
              title: 'The todo list could not be read',
              message:
                  '$loadError\nNothing will be saved over it until it reads '
                  'cleanly.',
              action: SettingsActionButton(
                label: 'Retry',
                compact: true,
                onTap: store.retry,
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
                            items: store.itemsIn(column),
                            store: store,
                            onEdit: (id) =>
                                editing.value = _EditRequest.edit(id),
                            onAdd: () =>
                                editing.value = _EditRequest.create(column),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

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
          HoverRegion(
            onTap: onClose,
            builder: (context, hovered) => Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ShellRadii.control),
                color: hovered ? theme.surfaceHover : const Color(0x00000000),
              ),
              child: Center(
                child: Text(
                  '✕',
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    color: theme.popupForeground.withValues(
                      alpha: hovered ? 0.9 : 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One column: its heading, its add button, and its cards — and the drop
/// target for the space below the last card.
class _ColumnView extends StatelessWidget {
  const _ColumnView({
    required this.column,
    required this.items,
    required this.store,
    required this.onEdit,
    required this.onAdd,
  });

  final TodoColumn column;
  final List<TodoItem> items;
  final TodoStore store;
  final ValueChanged<String> onEdit;
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
                : theme.controlSurface.withValues(alpha: 0.5),
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
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: theme.divider),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          editable ? 'Drop a card here' : '',
                          style: TextStyle(
                            fontSize: ShellFontSizes.secondary,
                            color: theme.popupForeground.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            8,
                            kTodoCardGap,
                            8,
                            // Room under the last card to drop onto.
                            48,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Padding(
                              key: ValueKey(item.id),
                              padding: const EdgeInsets.only(
                                bottom: kTodoCardGap,
                              ),
                              child: _DraggableCard(
                                item: item,
                                width: constraints.maxWidth - 16,
                                store: store,
                                onEdit: onEdit,
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A card that can be picked up, and that takes a drop *above* itself.
class _DraggableCard extends StatelessWidget {
  const _DraggableCard({
    required this.item,
    required this.width,
    required this.store,
    required this.onEdit,
  });

  final TodoItem item;
  final double width;
  final TodoStore store;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final face = _CardFace(item: item, today: store.now);
    final card = HoverRegion(
      onTap: () => onEdit(item.id),
      builder: (context, hovered) => _CardChrome(hovered: hovered, child: face),
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
                child: _CardChrome(hovered: true, lifted: true, child: face),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _CardChrome(hovered: false, child: face),
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

class _CardChrome extends StatelessWidget {
  const _CardChrome({
    required this.hovered,
    required this.child,
    this.lifted = false,
  });

  final bool hovered;
  final bool lifted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: hovered
            ? Color.alphaBlend(
                theme.surfaceHover.withValues(alpha: 0.5),
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
      child: child,
    );
  }
}

/// What a card shows: the title, the start of the body, and a line of facts —
/// when it is due, how it repeats, and when it arrived in this column.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.item, required this.today});

  final TodoItem item;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final dim = theme.popupForeground.withValues(alpha: 0.6);
    final due = item.due;
    final recurrence = item.recurrence;
    final title = item.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.isEmpty ? 'Untitled' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            fontWeight: FontWeight.w600,
            color: title.isEmpty ? dim : theme.popupForeground,
          ),
        ),
        if (item.body.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.body.trim(),
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
            if (due != null) _DueChip(item: item, due: due, today: today),
            if (recurrence != null)
              _Fact(
                icon: FontAwesomeIcons.repeat,
                label: recurrence.describe(),
              ),
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

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.color});

  final FaIconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final tint = color ?? theme.popupForeground.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: ShellFontSizes.caption - 1, color: tint),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: ShellFontSizes.caption, color: tint),
        ),
      ],
    );
  }
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
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _due, _every, _start]) {
      c.dispose();
    }
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
              autofocus: true,
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
