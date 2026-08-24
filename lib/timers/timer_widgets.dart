/// The UI over [TimersStore]: the row-and-controls the calendar page and the
/// clock module's popup both render, the composer that starts a new entry, and
/// the readout that sits next to the clock in the bar.
///
/// Every widget here takes its [TimersStore] as a parameter, defaulting to the
/// singleton only when it is actually read. That is the `ClockSource` seam the
/// calendar's clock column uses, and it is what lets these be widget-tested
/// against a hand-stepped store with no ticker behind it.
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/timers/timer_format.dart';
import 'package:graceful_shell/timers/timer_store.dart';

/// One entry's row in a list. Fixed, so the calendar page's list can be a
/// [ListView] with an `itemExtent`.
const double kTimerRowHeight = 42;

/// Height of the calendar page's timers strip.
///
/// Fixed rather than a fraction: the month grid above it keeps whatever is
/// left, and at the overlay's 800x500 minimum that has to stay a usable six
/// rows of dates. What is left over goes to the list, which scrolls — the
/// strip is sized to show the composer and a couple of entries, not every
/// entry the user can start.
const double kTimersPaneHeight = 190;

/// Width of the bar popup's card.
///
/// Pinned, for the reason `modules/sound_control.dart` documents: this popup
/// rebuilds while it is open (every readout, four times a second) and Flutter's
/// Linux popup resolves its placement once at map time, so a content-width card
/// would walk away from the bar as the digits changed.
const double kTimersPopupWidth = 264;

/// What the presets in the composer offer. Minutes, the unit the field's bare
/// numbers are read as.
const List<int> kTimerPresetMinutes = [1, 5, 10, 25];

FaIconData timerKindIcon(ShellTimerKind kind) =>
    kind == ShellTimerKind.stopwatch
    ? FontAwesomeIcons.stopwatch
    : FontAwesomeIcons.hourglassHalf;

/// `Timer · 5:00`, `Stopwatch · Paused` — what the entry is, and what it is
/// doing when that is not simply "counting".
String timerSubtitle(ShellTimer entry) {
  final kind = entry.kind == ShellTimerKind.stopwatch
      ? 'Stopwatch'
      : 'Timer · ${formatTimerDuration(entry.total)}';
  if (entry.finished) return '$kind · Finished';
  if (!entry.running) return '$kind · Paused';
  return kind;
}

/// One entry: what it is, where it has got to, and its three controls.
///
/// Shared verbatim between the calendar page and the bar popup — the two places
/// the user can reach a running timer — so a control added here is a control
/// both of them grow.
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
      readoutColor = theme.accent;
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
          FaIcon(
            timerKindIcon(entry.kind),
            size: 12,
            color: entry.finished
                ? theme.accent
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
                    fontSize: 10,
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
                ? FontAwesomeIcons.pause
                : FontAwesomeIcons.play,
            size: 11,
            onTap: () => store.toggle(entry.id),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.arrowRotateLeft,
            size: 11,
            onTap: () => store.reset(entry.id),
          ),
          // Stop is a removal, which is what makes the bar readout go away —
          // see the contract on [TimersStore].
          SettingsIconButton(
            icon: FontAwesomeIcons.stop,
            size: 11,
            onTap: () => store.stop(entry.id),
          ),
        ],
      ),
    );
  }
}

/// The duration field, its presets, and the two Start buttons.
class TimerComposer extends StatefulWidget {
  const TimerComposer({super.key, required this.store});

  final TimersStore store;

  @override
  State<TimerComposer> createState() => _TimerComposerState();
}

class _TimerComposerState extends State<TimerComposer> {
  String _text = '';

  /// Bumped to give [SettingsTextField] a new key, which is how the field is
  /// cleared: it seeds its controller from `initial` once and never re-reads
  /// it, so a started timer's text is dropped by rebuilding the field rather
  /// than by reaching into its state.
  int _generation = 0;

  Duration? get _parsed => parseDurationInput(_text);

  void _startTimer() {
    final duration = _parsed;
    if (duration == null) return;
    widget.store.startTimer(duration);
    setState(() {
      _text = '';
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SettingsTextField(
              key: ValueKey(_generation),
              initial: '',
              width: 86,
              hint: '5:00',
              onChanged: (value) => setState(() => _text = value),
              onSubmitted: (_) => _startTimer(),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Start timer',
              compact: true,
              primary: true,
              // Inert rather than hidden while the field is empty or
              // half-typed: a button that comes and goes under the pointer is
              // harder to hit than one that is simply dim.
              enabled: _parsed != null,
              onTap: _startTimer,
            ),
            const SizedBox(width: 6),
            SettingsActionButton(
              label: 'Stopwatch',
              compact: true,
              onTap: widget.store.startStopwatch,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Quick',
              style: TextStyle(
                fontSize: 10,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 8),
            for (final minutes in kTimerPresetMinutes) ...[
              _PresetChip(
                label: '${minutes}m',
                onTap: () =>
                    widget.store.startTimer(Duration(minutes: minutes)),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

/// The calendar page's strip: the composer over the list of what is running.
class TimersPane extends StatelessWidget {
  const TimersPane({super.key, required this.active, this.store});

  /// Whether the calendar is the tab the user is looking at.
  ///
  /// Required, not defaulted, for the reason `CalendarTab.active` is: the
  /// overlay body is an `IndexedStack` that keeps every tab alive once built,
  /// and the store notifies four times a second while anything is running — so
  /// a pane that subscribed unconditionally would re-lay its rows behind
  /// whatever tab the user moved on to. Inactive, it builds one static
  /// snapshot and listens to nothing.
  final bool active;

  /// Defaults to the singleton, and only when it is read — a widget test passes
  /// its own so no ticker is ever started behind the test zone.
  final TimersStore? store;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? TimersStore.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: active
          ? ListenableBuilder(
              listenable: store,
              builder: (context, _) => _buildContent(context, store),
            )
          : _buildContent(context, store),
    );
  }

  Widget _buildContent(BuildContext context, TimersStore store) {
    final theme = ThemeScope.of(context);
    final now = store.now;
    final entries = store.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'TIMERS & STOPWATCHES',
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (entries.length > 1)
              SettingsActionButton(
                label: 'Stop all',
                compact: true,
                onTap: store.stopAll,
              ),
          ],
        ),
        const SizedBox(height: 8),
        TimerComposer(store: store),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'Nothing running. Start one to see it beside the '
                    'clock.',
                    style: TextStyle(
                      fontSize: ShellFontSizes.secondary,
                      fontFamily: theme.fontFamily,
                      color: theme.muted,
                    ),
                  ),
                )
              // A ListView with a fixed extent, never a Column: the user
              // picks how many entries there are, and a Column overflows
              // the moment they pick one more than the strip is tall.
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: kTimerRowHeight,
                  itemCount: entries.length,
                  itemBuilder: (_, i) =>
                      TimerRow(entry: entries[i], now: now, store: store),
                ),
        ),
      ],
    );
  }
}

/// What the clock module's popup renders: every entry and all of its controls.
///
/// The card is built once and captured in a `WindowEntry` builder, so it reads
/// the theme from its own [ThemeScope] (supplied by the `ThemeProvider` the
/// module wraps it in) and the entries from the store — both live, which is
/// what keeps an open popup in step with a timer stopped from the calendar page
/// and with a theme changed underneath it.
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
        child: PopupBounceIn(
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
      ),
    );
  }
}

/// What the clock module puts beside the time.
///
/// One entry renders as its live readout; several render as one icon and a
/// count, because two countdowns and a stopwatch spelled out in a panel is a
/// bar module that resizes the whole panel every second. Either way the tap
/// opens the popup, which is where the controls are — so the bar can pause and
/// stop a timer without the overlay ever being opened.
///
/// The leading separator is part of this widget rather than of the clock's Row
/// so that "clock, rule, timer" appears and disappears as one thing.
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
              ? theme.accent
              : theme.foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 14,
              color: theme.foreground.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) => BarButton(
                active: active,
                onTapDown: (_) => onTap(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      timerKindIcon(only?.kind ?? ShellTimerKind.stopwatch),
                      size: 11,
                      color: style.color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      only != null
                          ? formatTimerDuration(only.displayAt(store.now))
                          : '${entries.length}',
                      style: style,
                    ),
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
