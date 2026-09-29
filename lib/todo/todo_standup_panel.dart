// The card the board's standup button opens: every summary taken so far to
// pick from and copy again, the button that takes a new one (opening the card
// does not — looking back at yesterday's must not start today's), and the way
// to invalidate the latest so the next one covers what it did.

import 'package:flutter/widgets.dart';

import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/todo/todo_standup.dart';
import 'package:moonswing/todo/todo_store.dart';

/// The standup card's width.
const double kTodoStandupPanelWidth = 760;

/// The width of the list of summaries down the card's left side.
const double kTodoStandupListWidth = 210;

/// The height of the list and the summary beside it, when there is a list.
const double kTodoStandupBodyHeight = 460;

/// The height of one row in that list.
const double kTodoStandupRowHeight = 44;

/// The standup card over a scrim that covers the board, showing
/// [TodoStore.standups] — newest first. A new summary is taken only from the
/// card's own "New summary" button.
class TodoStandupLayer extends StatelessWidget {
  const TodoStandupLayer({
    super.key,
    required this.store,
    required this.onDone,
    this.copy = copyTextToClipboard,
  });

  final TodoStore store;
  final VoidCallback onDone;

  /// How "Copy" copies; a test records instead of forking `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return GestureDetector(
      // Absorbs clicks meant for the board underneath.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: theme.scrim,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kTodoStandupPanelWidth.clamp(
                  0,
                  (constraints.maxWidth - 32).clamp(0, double.infinity),
                ),
                maxHeight: (constraints.maxHeight - 32).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: _StandupCard(store: store, onDone: onDone, copy: copy),
            ),
          ),
        ),
      ),
    );
  }
}

class _StandupCard extends StatefulWidget {
  const _StandupCard({
    required this.store,
    required this.onDone,
    required this.copy,
  });

  final TodoStore store;
  final VoidCallback onDone;
  final Future<ClipboardResult> Function(String text) copy;

  @override
  State<_StandupCard> createState() => _StandupCardState();
}

class _StandupCardState extends State<_StandupCard> {
  /// The summaries on show. Read from the store once and again after a new
  /// one is taken or the latest invalidated — the store announces neither.
  late List<StandupSummary> _summaries = widget.store.standups;

  /// Which of [_summaries] is shown; 0 is the latest.
  int _selected = 0;

  String? _message;
  bool _messageIsError = false;

  StandupSummary? get _shown =>
      _selected < _summaries.length ? _summaries[_selected] : null;

  void _select(int index) {
    if (index == _selected) return;
    setState(() {
      _selected = index;
      _message = null;
    });
  }

  Future<void> _copy() async {
    final shown = _shown;
    if (shown == null) return;
    final result = await widget.copy(shown.report);
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        ClipboardResult.copied => 'The summary is on the clipboard.',
        ClipboardResult.unavailable => 'Install $kClipboardPackage to copy it.',
        ClipboardResult.failed => '$kClipboardCommand could not copy it.',
      };
      _messageIsError = result != ClipboardResult.copied;
    });
  }

  void _generate() {
    if (widget.store.takeStandup() == null) return;
    setState(() {
      _summaries = widget.store.standups;
      _selected = 0;
      _message = null;
    });
  }

  void _invalidate() {
    final latest = _summaries.isEmpty ? null : _summaries.first;
    if (latest == null || !widget.store.invalidateLatestStandup()) return;
    setState(() {
      _summaries = widget.store.standups;
      _selected = 0;
      _messageIsError = false;
      final since = latest.since;
      _message = since == null
          ? 'Invalidated. The next summary will look back over the last '
                '24 hours.'
          : 'Invalidated. The next summary will count from '
                '${describeStandupMoment(since, now: widget.store.now)}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final shown = _shown;
    return Container(
      decoration: BoxDecoration(
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.accent),
        boxShadow: [BoxShadow(color: theme.popupShadowColor, blurRadius: 24)],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Standup',
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    fontWeight: FontWeight.w600,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              if (_selected == 0 && shown != null) ...[
                const SettingsInfoTip(
                  'Forgets the latest summary. The next one counts from where '
                  'it did, so it covers everything this one covered.',
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 110,
                  child: SettingsActionButton(
                    label: 'Invalidate',
                    onTap: _invalidate,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 120,
                child: SettingsActionButton(
                  label: 'New summary',
                  enabled: widget.store.editable,
                  onTap: _generate,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: SettingsActionButton(
                  label: 'Copy',
                  enabled: shown != null,
                  onTap: _copy,
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 14),
          Flexible(
            child: _summaries.length < 2
                ? _ReportBox(summary: shown)
                // One height whichever summary is picked, so the list does
                // not jump about under the pointer.
                : SizedBox(
                    height: kTodoStandupBodyHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: kTodoStandupListWidth,
                          child: _SummaryList(
                            summaries: _summaries,
                            selected: _selected,
                            now: widget.store.now,
                            onSelect: _select,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _ReportBox(summary: shown)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Every kept summary, newest first, one fixed-height row each.
class _SummaryList extends StatelessWidget {
  const _SummaryList({
    required this.summaries,
    required this.selected,
    required this.now,
    required this.onSelect,
  });

  final List<StandupSummary> summaries;
  final int selected;
  final DateTime now;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShellRadii.control),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemExtent: kTodoStandupRowHeight,
          scrollCacheExtent: const ScrollCacheExtent.pixels(
            kTodoStandupRowHeight * 10,
          ),
          itemCount: summaries.length,
          itemBuilder: (context, index) => RepaintBoundary(
            child: _SummaryRow(
              label: _labelOf(summaries[index], now),
              latest: index == 0,
              selected: index == selected,
              onTap: () => onSelect(index),
            ),
          ),
        ),
      ),
    );
  }

  static String _labelOf(StandupSummary summary, DateTime now) {
    final moment = describeStandupMoment(summary.takenAt, now: now);
    return '${moment[0].toUpperCase()}${moment.substring(1)}';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.latest,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool latest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected
              ? theme.accent.withValues(alpha: 0.18)
              : hovered
              ? theme.surfaceHover
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: theme.popupForeground,
                ),
              ),
            ),
            if (latest)
              Text(
                'Latest',
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: theme.accentText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The text of the summary on show, scrollable and selectable by copying.
class _ReportBox extends StatelessWidget {
  const _ReportBox({required this.summary});

  final StandupSummary? summary;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final summary = this.summary;
    return Container(
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.divider),
      ),
      child: SingleChildScrollView(
        // Keyed on the summary, so picking another starts at its top.
        key: ObjectKey(summary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          summary?.report ??
              'No summaries yet. "New summary" takes one of what was '
                  'finished, started and still to do.',
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            height: 1.4,
            color: summary == null
                ? theme.popupForeground.withValues(alpha: 0.6)
                : theme.popupForeground,
          ),
        ),
      ),
    );
  }
}
