/// The UI over [TimersStore]: the row-and-controls the clock module's popup
/// renders, the composer the overview's timer button opens (with its quick
/// timers, `quick_timers.dart`), and the readout
/// beside the clock in the bar. The overview's floating timers are
/// `overlay/sticky_notes/floating_timer_layer.dart`.
///
/// Every widget here takes its [TimersStore] as a parameter, defaulting to the
/// singleton only when it is actually read — the `ClockSource` seam, and what
/// lets these be widget-tested against a hand-stepped store with no ticker.
library;

import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter/widgets.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart' show ThemeConfig;
import 'package:moonswing/config_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/timers/quick_timers.dart';
import 'package:moonswing/timers/timer_format.dart';
import 'package:moonswing/timers/timer_sound.dart';
import 'package:moonswing/timers/timer_store.dart';

/// One entry's row in a list. Fixed, so the lists that render entries can be
/// [ListView]s with an `itemExtent`.
///
/// Sized for the row's two lines at readable sizes, not for the smallest they
/// could be set at.
const double kTimerRowHeight = 48;

/// What the composer's field starts with.
///
/// The primary button is therefore live the moment the pane is drawn: "give me
/// five minutes" is the common case, and typing it out was the entire cost of it.
/// Starting a timer puts the field back to this rather than emptying it.
const String kDefaultTimerDuration = '5:00';

/// Width of the bar popup's card.
///
/// Pinned, for the reason `modules/sound_control.dart` documents: this popup
/// rebuilds while open (every readout, four times a second) and Flutter's Linux
/// popup resolves its placement once at map time, so a content-width card would
/// walk away from the bar as the digits changed.
const double kTimersPopupWidth = 264;

ShellGlyph timerKindIcon(ShellTimerKind kind) =>
    kind == ShellTimerKind.stopwatch
    ? ShellGlyph.stopwatch
    : ShellGlyph.hourglass;

/// `Timer · 5:00`, `Tea · 3:00`, `Stopwatch · Paused` — what the entry is
/// (its name, where it has one), and what it is doing when that is not simply
/// "counting".
String timerSubtitle(ShellTimer entry) {
  final kind = entry.kind == ShellTimerKind.stopwatch
      ? 'Stopwatch'
      : '${entry.label ?? 'Timer'} · ${formatTimerDuration(entry.total)}';
  if (entry.finished) return '$kind · Finished';
  if (!entry.running) return '$kind · Paused';
  return kind;
}

/// One entry: what it is, where it has got to, and its three controls.
///
/// The bar popup's row: the way to a running timer while the overview is shut.
/// The overview's floating timers carry the same verbs in their menus.
class TimerRow extends StatelessWidget {
  const TimerRow({
    super.key,
    required this.entry,
    required this.now,
    required this.store,
  });

  final ShellTimer entry;

  /// The instant the readout is measured against, passed in rather than read
  /// per row so every row in a list agrees.
  final DateTime now;

  final TimersStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color readoutColor;
    if (entry.finished) {
      readoutColor = theme.accentText;
    } else if (entry.running) {
      readoutColor = theme.popupForeground;
    } else {
      readoutColor = theme.popupForeground.withValues(alpha: 0.55);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.control),
      ),
      child: Row(
        children: [
          ShellIcon(
            timerKindIcon(entry.kind),
            size: 12,
            color: entry.finished
                ? theme.accentText
                : theme.popupForeground.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatTimerDuration(entry.displayAt(now)),
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    fontFamily: theme.fontFamily,
                    color: readoutColor,
                    fontWeight: FontWeight.w600,
                    // Tabular, or the row's controls shuffle sideways on every
                    // digit that changes width.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  timerSubtitle(entry),
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.45),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SettingsIconButton(
            icon: entry.running
                ? ShellGlyph.pause
                : ShellGlyph.play,
            size: 11,
            onTap: () => store.toggle(entry.id),
          ),
          SettingsIconButton(
            icon: ShellGlyph.undo,
            size: 11,
            onTap: () => store.reset(entry.id),
          ),
          // Stop is a removal, which is what makes the bar readout go away —
          // see the contract on [TimersStore].
          SettingsIconButton(
            icon: ShellGlyph.stop,
            size: 11,
            onTap: () => store.stop(entry.id),
          ),
        ],
      ),
    );
  }
}

/// What the overview's timer button opens: the quick timers, the duration and
/// name fields, and the buttons that start a timer or keep it as a quick one.
///
/// The field arrives holding [kDefaultTimerDuration], so "five minutes" is one
/// Enter or one click, and any other length is typed straight over it. A quick
/// timer is one click: its chip starts it, named, and its × forgets it. Under
/// the buttons goes why the last alarm made no noise, if it made none: this is
/// where a user goes to set a timer, and the notification arrives whether or
/// not the sound worked, so an alarm that has quietly stopped working is
/// otherwise indistinguishable from one they switched off.
class TimerComposer extends StatefulWidget {
  const TimerComposer({
    super.key,
    required this.store,
    this.sound,
    this.config,
    this.onStarted,
    this.autofocus = false,
  });

  final TimersStore store;

  /// Where the alarm's failure is read from, defaulting to the singleton only
  /// when it is read — a widget test passes its own.
  final TimerSoundStore? sound;

  /// Where the quick timers are kept, defaulting to the shell's config. With
  /// neither — a test that loads no config — the composer offers none.
  final ConfigStore? config;

  /// A countdown was started, with this id.
  final ValueChanged<int>? onStarted;

  /// Whether the field takes the keyboard as it is first built.
  final bool autofocus;

  @override
  State<TimerComposer> createState() => _TimerComposerState();
}

/// The width of the composer's field labels, so the two fields start on one
/// edge.
const double _kComposerLabelWidth = 64;

class _TimerComposerState extends State<TimerComposer> {
  String _text = kDefaultTimerDuration;
  String _name = '';

  /// Bumped to give a [SettingsTextField] a new key, which is how a field is
  /// put back to its default: it seeds its controller from `initial` once and
  /// never re-reads it, so a started timer's text is reset by rebuilding the
  /// field rather than by reaching into its state. The name has its own, since
  /// saving a quick timer clears the name and keeps the length.
  int _generation = 0;
  int _nameGeneration = 0;

  QuickTimerBook? get _book {
    final config = widget.config ?? ConfigStore.maybeInstance;
    return config == null ? null : QuickTimerBook(config);
  }

  Duration? get _parsed => parseDurationInput(_text);

  bool get _canSave =>
      _parsed != null && normalizeQuickTimerName(_name).isNotEmpty;

  void _startTimer() {
    final duration = _parsed;
    if (duration == null) return;
    final id = widget.store.startTimer(
      duration,
      label: normalizeQuickTimerName(_name),
    );
    setState(() {
      _text = kDefaultTimerDuration;
      _name = '';
      _generation++;
      _nameGeneration++;
    });
    widget.onStarted?.call(id);
  }

  void _startQuick(QuickTimer timer) {
    final id = widget.store.startTimer(timer.duration, label: timer.name);
    widget.onStarted?.call(id);
  }

  void _save() {
    final duration = _parsed;
    final book = _book;
    if (duration == null || book == null) return;
    if (!book.save(_name, duration)) return;
    setState(() {
      _name = '';
      _nameGeneration++;
    });
  }

  Widget _label(ThemeConfig theme, String text) => SizedBox(
    width: _kComposerLabelWidth,
    child: Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.body,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.75),
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final book = _book;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (book != null)
          _QuickTimerShelf(
            book: book,
            onStart: _startQuick,
          ),
        Row(
          children: [
            _label(theme, 'Duration'),
            Expanded(
              child: SettingsTextField(
                key: ValueKey(_generation),
                initial: kDefaultTimerDuration,
                autofocus: widget.autofocus,
                // What the field accepts, shown where a placeholder goes: it
                // is the answer to "what may I type here?", and it is asked
                // exactly when the field has been cleared to type something.
                hint: '5, 1:30 or 1h30m',
                onChanged: (value) => setState(() => _text = value),
                onSubmitted: (_) => _startTimer(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _label(theme, 'Name'),
            Expanded(
              child: SettingsTextField(
                key: ValueKey(('name', _nameGeneration)),
                hint: 'Optional, e.g. Tea',
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kQuickTimerNameMaxLength),
                ],
                onChanged: (value) => setState(() => _name = value),
                onSubmitted: (_) => _startTimer(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsActionButton(
          label: 'Start timer',
          compact: true,
          primary: true,
          // Inert rather than hidden while the field is half-typed: a button
          // that comes and goes under the pointer is harder to hit than one
          // that is simply dim.
          enabled: _parsed != null,
          onTap: _startTimer,
        ),
        if (book != null) ...[
          const SizedBox(height: 6),
          SettingsActionButton(
            label: 'Save as quick timer',
            icon: ShellGlyph.add,
            compact: true,
            // A quick timer is found again by its name, so it needs one.
            enabled: _canSave,
            onTap: _save,
          ),
        ],
        _TimerSoundError(sound: widget.sound ?? TimerSoundStore.instance),
      ],
    );
  }
}

/// The quick timers, as one chip each, above the composer's fields.
///
/// Its own subscription to the config, so the shelf follows a quick timer
/// added here, removed from another monitor's overview or hand-edited into
/// the file, and the fields below are not rebuilt by any of it. Nothing at
/// all while there are none — the Save button below says how to make one.
class _QuickTimerShelf extends StatelessWidget {
  const _QuickTimerShelf({required this.book, required this.onStart});

  final QuickTimerBook book;
  final ValueChanged<QuickTimer> onStart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: book.config,
    builder: (context, _) {
      final timers = book.timers;
      if (timers.isEmpty) return const SizedBox.shrink();
      final theme = ThemeScope.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick timers',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final timer in timers)
                  QuickTimerChip(
                    key: ValueKey(timer),
                    timer: timer,
                    onStart: () => onStart(timer),
                    onRemove: () => book.remove(timer),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// One quick timer: its name and length, a click to start it, and an × to
/// forget it.
class QuickTimerChip extends StatelessWidget {
  const QuickTimerChip({
    super.key,
    required this.timer,
    required this.onStart,
    required this.onRemove,
  });

  final QuickTimer timer;
  final VoidCallback onStart;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own layer, so the hover tint repaints a chip and not the card.
    return RepaintBoundary(
      child: SettingsTooltip(
        message: 'Start ${timer.name}',
        child: HoverRegion(
          onTap: onStart,
          builder: (context, hovered) => Container(
            constraints: const BoxConstraints(
              minHeight: ShellSizes.minTapTarget,
            ),
            padding: const EdgeInsets.only(left: 10, right: 2),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(theme.surfaceHover, theme.controlSurface)
                  : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: Border.all(
                color: hovered ? theme.accent : const Color(0x00000000),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShellIcon(
                  ShellGlyph.play,
                  size: 9,
                  color: hovered
                      ? theme.accentText
                      : theme.popupForeground.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    timer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.secondary,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  formatCompactDuration(timer.duration),
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                SettingsIconButton(
                  icon: ShellGlyph.close,
                  size: 8,
                  box: ShellSizes.iconButtonDense,
                  tooltip: 'Forget ${timer.name}',
                  onTap: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why the last alarm made no noise, or nothing at all.
///
/// Its own widget so it is its own subscription and its own repaint boundary:
/// the reason changes at most once per countdown, and the field above it on
/// every keystroke.
class _TimerSoundError extends StatelessWidget {
  const _TimerSoundError({required this.sound});

  final TimerSoundStore sound;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sound,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final reason = sound.error;
    if (reason == null) return const SizedBox.shrink();
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          reason,
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            fontFamily: theme.fontFamily,
            color: kErrorColor,
          ),
        ),
      ),
    );
  }
}

/// What the clock module's popup renders: every entry and all of its controls.
///
/// The card is built once and captured in a `WindowEntry` builder, so it reads
/// the theme from its own [ThemeScope] and the entries from the store — both
/// live, which keeps an open popup in step with a timer stopped from the
/// overview and with a theme changed underneath it.
class TimersPopupContent extends StatelessWidget {
  const TimersPopupContent({super.key, this.store});

  final TimersStore? store;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? TimersStore.instance;
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          color: theme.popupForeground,
          fontSize: ShellFontSizes.body,
          fontFamily: theme.fontFamily,
          decoration: TextDecoration.none,
        ),
        child: PopupCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final now = store.now;
              final entries = store.entries;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        height: kTimerRowHeight,
                        child: TimerRow(entry: entry, now: now, store: store),
                      ),
                    if (entries.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: SettingsActionButton(
                          label: 'Stop all',
                          compact: true,
                          onTap: store.stopAll,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What the clock module puts beside the time.
///
/// One entry renders as its live readout; several render as one icon and a count,
/// because two countdowns and a stopwatch spelled out is a bar module that
/// resizes the whole panel every second. Either way the tap opens the popup,
/// which is where the controls are — so the bar can pause and stop a timer
/// without the overlay ever being opened.
///
/// The leading separator is part of this widget rather than of the clock's Row so
/// that "clock, rule, timer" appears and disappears as one thing.
class TimerBarIndicator extends StatelessWidget {
  const TimerBarIndicator({
    super.key,
    required this.onTap,
    this.store,
    this.active = false,
  });

  /// Handed the indicator's own [BuildContext], because that is what the
  /// popup is anchored to: called with the clock module's context instead, the
  /// card would centre itself on the date and time as well.
  final void Function(BuildContext context) onTap;

  final TimersStore? store;

  /// Whether the popup this opens is showing.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? TimersStore.instance;
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final entries = store.entries;
        if (entries.isEmpty) return const SizedBox.shrink();
        final only = store.onlyEntry;
        final style = TextStyle(
          fontSize: ShellFontSizes.title,
          color: only != null && only.finished
              ? theme.accentText
              : theme.foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        // Along the bar either way: on a side bar the rule lies flat under
        // the clock, the glyph sits over the readout, and a running time is
        // turned on its side as the clock is. A bare count is short enough to
        // read upright.
        return BarFlex(
          children: [
            BarDivider(
              length: 14,
              margin: 8,
              color: theme.foreground.withValues(alpha: 0.3),
            ),
            Builder(
              builder: (context) => BarButton(
                active: active,
                onTapDown: (_) => onTap(context),
                child: BarFlex(
                  spacing: 6,
                  verticalSpacing: 4,
                  children: [
                    ShellIcon(
                      timerKindIcon(only?.kind ?? ShellTimerKind.stopwatch),
                      size: 11,
                      color: style.color,
                    ),
                    if (only != null)
                      BarRotated(
                        child: Text(
                          formatTimerDuration(only.displayAt(store.now)),
                          style: style,
                        ),
                      )
                    else
                      BarText('${entries.length}', style: style),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
