/// The UI over [TimersStore]: the row-and-controls the calendar page and the
/// clock module's popup both render, the composer that starts a new entry, and
/// the readout beside the clock in the bar.
///
/// Every widget here takes its [TimersStore] as a parameter, defaulting to the
/// singleton only when it is actually read — the `ClockSource` seam, and what
/// lets these be widget-tested against a hand-stepped store with no ticker.
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/timers/timer_format.dart';
import 'package:graceful_shell/timers/timer_sound.dart';
import 'package:graceful_shell/timers/timer_store.dart';

/// One entry's row in a list. Fixed, so the lists that render entries can be
/// [ListView]s with an `itemExtent`.
///
/// Sized for the row's two lines at the readable sizes the calendar page moved
/// to, not for the smallest they could be set at.
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
          FaIcon(
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

/// The duration field and the two Start buttons.
///
/// Two rows rather than one: the composer sits in the calendar's clock column,
/// narrower than a labelled field and two buttons side by side. The field is
/// labelled because it is the one control on this page a user has to be told what
/// to put in, and its placeholder spells out the three forms it takes.
class TimerComposer extends StatefulWidget {
  const TimerComposer({super.key, required this.store});

  final TimersStore store;

  @override
  State<TimerComposer> createState() => _TimerComposerState();
}

class _TimerComposerState extends State<TimerComposer> {
  String _text = kDefaultTimerDuration;

  /// Bumped to give [SettingsTextField] a new key, which is how the field is
  /// put back to [kDefaultTimerDuration]: it seeds its controller from
  /// `initial` once and never re-reads it, so a started timer's text is reset
  /// by rebuilding the field rather than by reaching into its state.
  int _generation = 0;

  Duration? get _parsed => parseDurationInput(_text);

  void _startTimer() {
    final duration = _parsed;
    if (duration == null) return;
    widget.store.startTimer(duration);
    setState(() {
      _text = kDefaultTimerDuration;
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
            // Beside the field rather than over it: every line this composer
            // takes is a line the list of what is running does not get, and
            // the section is half a column.
            Text(
              'Duration',
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SettingsTextField(
                key: ValueKey(_generation),
                initial: kDefaultTimerDuration,
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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: 'Start timer',
                compact: true,
                primary: true,
                // Inert rather than hidden while the field is half-typed: a
                // button that comes and goes under the pointer is harder to hit
                // than one that is simply dim.
                enabled: _parsed != null,
                onTap: _startTimer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsActionButton(
                label: 'Stopwatch',
                compact: true,
                onTap: widget.store.startStopwatch,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The calendar page's timers section: the composer over the list of what is
/// running.
///
/// It sits under the world clocks and is given half of what is left below them,
/// so the creator is on screen without a scroll and the entries grow into the
/// same space. It adds no horizontal padding of its own — the column supplies
/// that, and a second inset would step the section in from the clocks above.
class TimersPane extends StatelessWidget {
  const TimersPane({super.key, required this.active, this.store, this.sound});

  /// Whether the calendar is the tab the user is looking at.
  ///
  /// Required, not defaulted, for `CalendarTab.active`'s reason: the overlay body
  /// is an `IndexedStack` that keeps every tab alive, and the store notifies four
  /// times a second while anything runs — so a pane that subscribed
  /// unconditionally would re-lay its rows behind whatever tab the user moved on
  /// to. Inactive, it builds one static snapshot and listens to nothing.
  final bool active;

  /// Defaults to the singleton, and only when it is read — a widget test passes
  /// its own so no ticker is ever started behind the test zone.
  final TimersStore? store;

  /// Where the alarm's failure is read from, defaulting to the singleton on the
  /// same terms as [store].
  ///
  /// It is rendered here because this pane is the one place a user goes to set
  /// a timer: the notification arrives whether or not the sound worked, so an
  /// alarm that has quietly stopped working is otherwise indistinguishable from
  /// one they switched off.
  final TimerSoundStore? sound;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? TimersStore.instance;
    final sound = this.sound ?? TimerSoundStore.instance;
    return active
        ? ListenableBuilder(
            listenable: store,
            builder: (context, _) => _buildContent(context, store, sound),
          )
        : _buildContent(context, store, sound);
  }

  Widget _buildContent(
    BuildContext context,
    TimersStore store,
    TimerSoundStore sound,
  ) {
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
                'Timers & stopwatches',
                style: TextStyle(
                  fontSize: ShellFontSizes.label,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
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
        // Its own subscription rather than a merge with the entries above it.
        // Two reasons, and they pull the same way: the alarm's reason changes
        // at most once per countdown while the rows tick four times a second,
        // and `Listenable.merge` built in a `build` mints a fresh object every
        // rebuild, which an `AnimatedWidget` answers by re-subscribing — sixty
        // times a minute here, to a store that almost never moves.
        _TimerSoundError(sound: sound, listening: active),
        const SizedBox(height: 8),
        Expanded(
          // The composer is the list's first item rather than a fixed header over
          // it. This section is half of a column whose height follows the
          // output's, so on a short display that half can be shorter than the
          // composer is tall: as a header that overflows, as an item it scrolls,
          // and the rows keep their fixed extent either way.
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: entries.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TimerComposer(store: store),
                      if (entries.isEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Nothing running. Start one to see it beside the '
                          'clock.',
                          style: TextStyle(
                            fontSize: ShellFontSizes.body,
                            fontFamily: theme.fontFamily,
                            color: theme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              final entry = entries[index - 1];
              return SizedBox(
                height: kTimerRowHeight,
                child: TimerRow(entry: entry, now: now, store: store),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Why the last alarm made no noise, or nothing at all.
///
/// Its own widget so it is its own subscription and its own repaint boundary:
/// the rows above it re-lay themselves four times a second, and a reason that
/// rebuilt with them would be measuring a paragraph on every tick.
class _TimerSoundError extends StatelessWidget {
  const _TimerSoundError({required this.sound, required this.listening});

  final TimerSoundStore sound;

  /// False on an inactive tab, which subscribes to nothing at all — the pane's
  /// own rule, for the reason `TimersPane.active` documents.
  final bool listening;

  @override
  Widget build(BuildContext context) => listening
      ? ListenableBuilder(
          listenable: sound,
          builder: (context, _) => _build(context),
        )
      : _build(context);

  Widget _build(BuildContext context) {
    final reason = sound.error;
    if (reason == null) return const SizedBox.shrink();
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
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
/// live, which keeps an open popup in step with a timer stopped from the calendar
/// page and with a theme changed underneath it.
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
