// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart' show ThemeConfig;
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/root_modal.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/popup_transition.dart';
import 'package:graceful_shell/search_list.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// Themed form controls shared by the panels inside the settings overlay.
///
/// Extracted from `shell.dart` when the calendar tab needed the same section
/// headers, rows, text fields, and icon buttons: two copies of this styling
/// would drift apart the first time the theme changed.

// ---------------------------------------------------------------------------
// Subscription seams
// ---------------------------------------------------------------------------

/// Rebuilds [builder] only when [selector]'s value changes between notifies of
/// [listenable].
///
/// The stores behind the settings UI notify far more often than the values a
/// given widget renders actually move: [ConfigStore] notifies on every `set`,
/// which is once per keystroke in any field anywhere in the pane, and
/// `ThemeStore` notifies on every frame of a colour-picker drag. A plain
/// [ListenableBuilder] around a page therefore rebuilds every row of it for one
/// digit typed into one of them.
///
/// This is the seam that narrows that: it holds the last selected value,
/// re-reads it on each notify, and `setState`s only when `==` says it moved.
/// Generalized out of `settings/shell/appearance.dart`, where it was written
/// for the theme editor and named for it.
class StoreSelector<T> extends StatefulWidget {
  const StoreSelector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<StoreSelector<T>> createState() => _StoreSelectorState<T>();
}

class _StoreSelectorState<T> extends State<StoreSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.selector();
    widget.listenable.addListener(_onNotify);
  }

  @override
  void didUpdateWidget(covariant StoreSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_onNotify);
      widget.listenable.addListener(_onNotify);
    }
    // A parent rebuild hands in a fresh selector closure; re-read so a value
    // that changed while this widget was not listening to it is not stale.
    _value = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onNotify);
    super.dispose();
  }

  void _onNotify() {
    final next = widget.selector();
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// One [ConfigStore] key, and only the widgets that render it.
///
/// [StoreSelector] specialized to the shape every settings section wants. The
/// page-level `ListenableBuilder` this replaces rebuilt all forty-five rows of
/// the Appearance pane — `background.dart`'s `existsSync` sweep and
/// `panels.dart`'s three `Module.registeredKeys` allocations included — for one
/// digit typed into one field.
///
/// Wrap the row's *control*, and wrap anything else whose text depends on the
/// same key: `power.dart`'s hint under the picker reads the action, so it is
/// inside the same [ConfigValue] as the picker itself. A control that owns its
/// own `TextEditingController` and reads `initial` once still belongs in one —
/// the selector's `==` check means a notify that did not move this key does not
/// even `setState`.
class ConfigValue<T> extends StatelessWidget {
  const ConfigValue({
    super.key,
    required this.store,
    required this.path,
    required this.builder,
    this.fallback,
  });

  final ConfigStore store;

  /// The `config.toml` path, as [ConfigStore.get] takes it.
  final List<String> path;

  /// Answered in place of a missing or wrongly-typed value, so the builder's
  /// argument is the value the row should render rather than a null it has to
  /// re-default itself.
  final T? fallback;

  final Widget Function(BuildContext context, T? value) builder;

  @override
  Widget build(BuildContext context) => StoreSelector<T?>(
    listenable: store,
    selector: () => store.get<T>(path) ?? fallback,
    builder: builder,
  );
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
    this.trailing,
  });

  final String label;
  final List<Widget> children;

  /// Right-aligned action on the section's own heading row — the same slot
  /// [SettingsSubLabel.trailing] gives a list inside a section, for a section
  /// whose whole body *is* the collection (the theme picker's "New theme…").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeading(label: label, trailing: trailing),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

/// The heading row [SettingsSection] and [SliverSettingsSection] share.
///
/// Extracted so a section's label cannot render one way in the box form and
/// another in the sliver form — the drift this library exists to prevent.
class SettingsSectionHeading extends StatelessWidget {
  const SettingsSectionHeading({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    if (trailing == null) return SettingsSectionLabel(label);
    return Row(
      children: [
        Expanded(child: SettingsSectionLabel(label)),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

/// [SettingsSection] for a section that *is* the page, in a page whose
/// scroller is a [CustomScrollView].
///
/// Same label, same trailing slot, same children — emitted as slivers so the
/// list is lazy and each child gets its repaint boundary from the sliver rather
/// than by hand. The box [SettingsSection] is still what a section *nested
/// inside another scroller* wants (the audio tabs, the display page, the file
/// picker), and is unchanged.
///
/// Laziness is the point, and it is worth stating what it does and does not
/// buy. A `Column` in a `SingleChildScrollView` is laid out once, so scrolling
/// it costs no layout either way — that half was fixed by the repaint boundary
/// [SettingsRow] carries. What this buys is that a child off the bottom of the
/// viewport is never *mounted*: `background.dart` puts up to a hundred and
/// twenty `Image.file` tiles on one page, and `Image` resolves its provider on
/// mount rather than on first paint, so every one of them decoded whether or
/// not it was ever scrolled to.
class SliverSettingsSection extends StatelessWidget {
  const SliverSettingsSection({
    super.key,
    required this.label,
    required this.children,
    this.trailing,
  });

  final String label;

  /// Box widgets, as [SettingsSection.children] takes them. A child that is
  /// already a sliver belongs in [slivers] instead.
  final List<Widget> children;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SettingsSectionHeading(label: label, trailing: trailing),
        ),
      ),
      // `SliverList.list`, not `.builder`: these sections' children are
      // declarative tables whose widget *construction* is trivial. What is
      // expensive is element inflation and layout, and `SliverChildListDelegate`
      // is already lazy in exactly that — which is what lets every section keep
      // its existing `List<Widget> children` shape.
      //
      // `addRepaintBoundaries` stays on (its default), which does mean a
      // [SettingsRow] child ends up inside two boundaries — its own and the
      // delegate's. That is one extra `OffsetLayer` per row and it is the right
      // trade: [SettingsRow] cannot drop its boundary, because it is also used
      // nested several levels down inside the *box* sections on the audio and
      // display pages, where nothing else would supply one.
      SliverList.list(children: children),
    ],
  );
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// The heading over one list inside a section — "Pinned items", "Shown",
/// "Left modules".
///
/// [trailing] is the list's own action, right-aligned on the heading row. That
/// is where every add button in the settings UI lives: an adder under a list
/// walks away from the user as the list grows — off the bottom of the scroll
/// view once it is long enough — while the heading is where the list starts
/// and stays put, and the button lands in the same column as the rows' own
/// icons. [SettingsStringListEditor] puts its adder here itself.
class SettingsSubLabel extends StatelessWidget {
  const SettingsSubLabel(this.text, {super.key, this.trailing});

  final String text;

  /// Right-aligned action for the list this heading names, or null for a
  /// heading with nothing to add to.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontFamily: theme.fontFamily,
        color: theme.accent,
        fontWeight: FontWeight.w600,
      ),
    );
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: trailing == null
          ? label
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                trailing,
              ],
            ),
    );
  }
}

class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
      ),
    );
  }
}

/// A labelled form row: the label on the left, the [control] on the right.
///
/// It carries a [RepaintBoundary], and that is load-bearing rather than
/// decorative. A settings page scrolls in a `SingleChildScrollView`, whose
/// `_RenderSingleChildViewport` *is* a repaint boundary but whose child is
/// painted inline — so without a boundary somewhere below it, a mark landing
/// anywhere on the page re-records the whole page's display list, and the page
/// is never eligible for the raster cache (the engine only caches
/// repaint-boundary layers that stay identical across consecutive frames).
/// Every control on these pages is a [HoverRegion], which `setState`s on enter
/// and exit, and `MouseTracker` re-runs its hit test after any frame that
/// changed the layer tree — so a stationary pointer over a scrolling list marks
/// one row after another as the rows slide under it.
///
/// The boundary goes *here*, and this is the granularity to keep. Not per
/// [SettingsSection] child, which would boundary the `SettingsHint` paragraphs
/// that never change and would add a handful of retained layers inside each
/// already-boundaried `ListView` item on the audio and display pages; not per
/// icon button, which is a retained layer for a 26px box already inside one of
/// these. [SettingsRow] is the intersection of "repeats thirty to forty-five
/// times a page" and "repaints on its own".
///
/// The rule that leaves behind, for anything the library does not cover:
/// **anything that hovers has a [RepaintBoundary] above its [HoverRegion],
/// unless it is inside a [SettingsRow], which carries one for it.**
///
/// A boundary contains a repaint and nothing else, so the companion discipline
/// is `calendar/clock_column.dart`'s: keep whatever a `HoverRegion.builder`
/// returns hover-*dependent*, and hoist the rest into the enclosing `build`.
/// An identical child widget is one the framework skips outright, which is what
/// makes the contained rebuild a decoration rather than a paragraph.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.control,
    this.alignTop = false,
  });

  final String label;
  final Widget control;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: alignTop
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: alignTop ? 10 : 0),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            control,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = value ? theme.accent : theme.divider;
    return HoverRegion(
      onTap: () => onChanged(!value),
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: ShellDurations.base,
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: hovered ? color.withValues(alpha: 0.8) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: ShellDurations.base,
                curve: Curves.easeInOut,
                left: value ? 22 : 2,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
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

class SettingsSegmented extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final o in options)
          SettingsOptionButton(
            label: '${o[0].toUpperCase()}${o.substring(1)}',
            selected: o == value,
            onTap: () => onChanged(o),
          ),
      ],
    );
  }
}

class SettingsOptionButton extends StatelessWidget {
  const SettingsOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final Color bg;
        if (selected) {
          bg = theme.accent;
        } else if (hovered) {
          bg = theme.surfaceHover;
        } else {
          bg = theme.controlSurface;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ShellRadii.pill),
            border: Border.all(color: selected ? theme.accent : theme.divider),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: selected ? const Color(0xFFFFFFFF) : theme.popupForeground,
            ),
          ),
        );
      },
    );
  }
}

/// A stretch-to-fit action button: accent-filled when [primary], quiet
/// otherwise. Shows a [LoadingIndicator] and refuses taps while [loading] or
/// not [enabled].
///
/// Extracted from the `_ActionButton` clones in the audio and display panes
/// (display's carried the superset: the [enabled] flag and the theme font).
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.loading = false,
    this.enabled = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool loading;
  final bool enabled;

  /// The dense inline form used beside a list row (the bluetooth pane's
  /// Connect/Disconnect): tighter padding and the secondary font size, sized
  /// to its label rather than stretched under a form.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final canTap = enabled && !loading;
    return HoverRegion(
      enabled: canTap,
      onTap: onTap,
      builder: (context, hovered) {
        final Color bg;
        if (primary) {
          bg = hovered && canTap
              ? theme.accent.withValues(alpha: 0.85)
              : canTap
              ? theme.accent
              : theme.accent.withValues(alpha: 0.4);
        } else {
          bg = hovered && canTap ? theme.surfaceHover : theme.divider;
        }
        return Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
              : const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Center(
            child: loading
                ? const LoadingIndicator(size: 14)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: compact
                          ? ShellFontSizes.secondary
                          : ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      color: primary ? kOnAccent : theme.popupForeground,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// A small accent-tinted pill marking a list row's state — "Connected" on the
/// network and bluetooth device lists.
///
/// Extracted from the `_ConnectedBadge` clones in the network and bluetooth
/// panes, identical but for the network one carrying the theme font (the
/// superset). The label is a parameter because the state a row wants to
/// announce is not always "Connected".
class SettingsBadge extends StatelessWidget {
  const SettingsBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: ShellFontSizes.caption,
          fontFamily: theme.fontFamily,
          color: theme.accent,
        ),
      ),
    );
  }
}

/// A quiet refresh affordance: a rotate-arrows icon beside its [label],
/// transparent at rest with a hover fill. The default label is "Scan"; the
/// error states pass "Retry".
///
/// Extracted from the `_RescanButton` clones in the network and bluetooth
/// panes, identical but for the network one carrying the theme font (the
/// superset). Not folded into [SettingsIconButton]: this is a labelled pill
/// with a hover-filled background, not a bare icon, and it carries no spin
/// state — both panes rebuild into a full-body loader while scanning.
class SettingsRescanButton extends StatelessWidget {
  const SettingsRescanButton({
    super.key,
    required this.onTap,
    this.label = 'Scan',
  });

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final theme = ThemeScope.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : null,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.arrowsRotate,
                size: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One row of a [SettingsDropdown]: the [value] it stands for, the [label]
/// shown for it, an optional dim [detail] tag after the label (the display
/// pane marks its preferred mode this way), and an optional [description] —
/// a sentence set *under* the label.
///
/// The two dim slots are not interchangeable, and conflating them is what
/// broke the popup-animation row: [detail] is a word or two that shares the
/// label's line and is laid out at whatever width it asks for, so a sentence
/// put there takes the whole row, ellipsises the label to nothing and is then
/// clipped at the card's edge. A [description] wraps, and is what makes the
/// card size itself to the prose rather than to the trigger it drops out of —
/// see [SettingsDropdown.cardWidth].
class SettingsDropdownItem<T> {
  const SettingsDropdownItem({
    required this.value,
    required this.label,
    this.detail,
    this.description,
  });

  final T value;
  final String label;
  final String? detail;
  final String? description;
}

/// The card width a described dropdown takes when its caller names none.
///
/// Wider than any settings row's control, which is the whole point: a row of
/// prose cannot be read in the width of the trigger showing "Slide and fade".
const double _kDescribedCardWidth = 340;

/// How tall a described card may grow before it scrolls. Enough for the seven
/// popup effects; a longer list scrolls as any other does.
const double _kDescribedMaxHeight = 420;

/// A described row's padding above and below its two lines, and the gap
/// between them.
const double _kDescribedRowPadding = 7;
const double _kDescribedRowGap = 3;

/// How many lines of a [SettingsDropdownItem.description] are drawn. Beyond
/// this the sentence ellipsises — a dropdown row is not a paragraph.
const int _kDescriptionMaxLines = 3;

/// The row extent a described dropdown needs, measured rather than guessed.
///
/// The rows are a *fixed* extent — the generic's keyboard reveal is arithmetic
/// over it, not a measurement — so the one number has to be the tallest row's,
/// and it moves with the theme: the same sentence is two lines under one font
/// and three under another, and `font_size` scales the whole
/// [ShellFontSizes] ladder through a [TextScaler]. Measuring with the very
/// styles the row renders in is the rule `TrackMarquee` and `fitFortuneText`
/// already state.
double describedDropdownRowHeight({
  required Iterable<String> descriptions,
  required double contentWidth,
  required TextStyle labelStyle,
  required TextStyle descriptionStyle,
  required TextScaler textScaler,
}) {
  double measure(String text, TextStyle style, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: '\u2026',
    )..layout(maxWidth: contentWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  var tallest = 0.0;
  for (final description in descriptions) {
    final height = measure(description, descriptionStyle, _kDescriptionMaxLines);
    if (height > tallest) tallest = height;
  }
  // 'Ag' rather than the labels themselves: the label is one line by
  // construction, so what is wanted is the line height of the style.
  final label = measure('Ag', labelStyle, 1);
  return label + _kDescribedRowGap + tallest + 2 * _kDescribedRowPadding;
}

/// A bordered trigger showing the selected item's label, dropping a list of
/// the items *over* the pane rather than pushing it into the layout — the same
/// floating card the font picker uses, through the same
/// [AnchoredSearchDropdown]. A [selected] value no item carries shows an em
/// dash.
///
/// It used to expand inline, which is what made it the odd control out: a
/// dropdown that re-lays its own pane pushes everything under it down the
/// moment it opens, and on the audio and display pages that is the rest of the
/// form. The list floats in the **root** overlay for the reason
/// [SettingsColorField] documents — the settings content pane is a nested
/// `Navigator` whose `Overlay` would clip it — which means every host needs a
/// root `Overlay` above it; inside the settings window `SettingsOverlay`
/// supplies one.
///
/// The filter field appears only past [searchFrom] items: a search box over
/// the two outputs a machine has is chrome asking to be typed into for no
/// gain, while the thirty modes a monitor reports genuinely want one.
///
/// [cardWidth] is the opt-out from all of that, for the list whose rows carry
/// prose rather than a name — see [SettingsDropdownItem.description].
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.searchFrom = 8,
    this.cardWidth,
  });

  final List<SettingsDropdownItem<T>> items;
  final T? selected;
  final ValueChanged<T> onSelected;

  /// The item count from which the card carries a filter field.
  final int searchFrom;

  /// Float the card at this width instead of sizing it to the trigger.
  ///
  /// The trigger is a control at the right-hand end of a settings row and is
  /// only as wide as the value it is showing, so a card matched to it is only
  /// as wide as the word "Fade" — which is right for a list of names and
  /// hopeless for one whose rows explain themselves. A card with its own width
  /// therefore also anchors its *right* edge to the trigger's, growing
  /// leftwards over the pane rather than rightwards off it:
  /// [AnchoredSearchDropdown.alignRight]'s reasoning, reached from the other
  /// direction.
  ///
  /// Defaulted for a list whose items carry a
  /// [SettingsDropdownItem.description], since that is the shape that needs
  /// it; passing one explicitly is how a caller asks for a different width.
  final double? cardWidth;

  String get _selectedLabel {
    for (final item in items) {
      if (item.value == selected) return item.label;
    }
    return '—';
  }

  bool get _described => items.any((item) => item.description != null);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final described = _described;
    final width = cardWidth ?? (described ? _kDescribedCardWidth : null);
    final rowHeight = described && width != null
        ? describedDropdownRowHeight(
            descriptions: [
              for (final item in items)
                if (item.description != null) item.description!,
            ],
            contentWidth: dropdownContentWidth(width),
            // Merged over the ambient default the way `Text` itself merges
            // it: the card is built under the same `DefaultTextStyle` as this
            // trigger, and a measurement that skipped it would be taken in a
            // style with a different line height from the one drawn.
            labelStyle: DefaultTextStyle.of(
              context,
            ).style.merge(_dropdownLabelStyle(theme, selected: false)),
            descriptionStyle: DefaultTextStyle.of(
              context,
            ).style.merge(_dropdownDescriptionStyle(theme)),
            textScaler:
                MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
          )
        : 34.0;
    return AnchoredSearchDropdown<SettingsDropdownItem<T>>(
      // The card drops out of the trigger, so it is the trigger's width — a
      // fixed one would read as a different control on a row that stretches.
      // Unless the caller named one, in which case it is that, anchored to the
      // trigger's right edge; see [cardWidth].
      matchTriggerWidth: width == null,
      width: width ?? 240,
      alignRight: width != null,
      showSearch: items.length >= searchFrom,
      rowHeight: rowHeight,
      // Tall enough for the whole list where the list is short, so a card
      // that has been given room to explain itself is not also made to
      // scroll; a longer one still stops at [_kDescribedMaxHeight].
      maxHeight: width == null
          ? 260
          : math.min(
              _kDescribedMaxHeight,
              items.length * rowHeight + kDropdownCardPadding,
            ),
      // Closes the open list when what it is listing moves underneath it, the
      // guard the font field takes against a stale pick: the card is an
      // OverlayEntry and does not rebuild on the host's setState, so its rows
      // would go on marking whichever device *was* the default one — and, when
      // one is plugged in or unplugged, go on offering the ones that were
      // there when it opened. The inline list this replaced rebuilt with the
      // pane and needed neither.
      closeKey: Object.hash(selected, items.length),
      filter: (query) {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return items;
        return items
            .where((item) => item.label.toLowerCase().contains(q))
            .toList(growable: false);
      },
      // Open highlighted on the current item rather than at the top of a
      // monitor's mode list. -1 (a selection no item carries) starts at the
      // top, which is what the generic does with it.
      initialHighlight: (list) =>
          list.indexWhere((item) => item.value == selected),
      onSelected: (item) => onSelected(item.value),
      itemBuilder: (context, item, _) =>
          _DropdownRow<T>(item: item, selected: item.value == selected),
      triggerBuilder: (context, open, toggle) =>
          _DropdownTrigger(label: _selectedLabel, open: open, onTap: toggle),
    );
  }
}

class _DropdownTrigger extends StatelessWidget {
  const _DropdownTrigger({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final theme = ThemeScope.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.control),
            border: Border.all(
              color: open || hovered ? theme.accent : theme.divider,
            ),
          ),
          // The trigger stretches to whatever width it is given and shrinks
          // to its label when it is given none. Both halves are needed: a
          // dropdown is nearly always handed a bounded width (an `Expanded`, a
          // `ListView`'s cross axis) and has to fill it, or the card
          // `matchTriggerWidth` sizes to the trigger reads as a different
          // control from the row it drops out of. But a `SettingsRow` lays its
          // `control` out as an *inflexible* child of a `Row`, which per
          // `RenderFlex` means unbounded width — and an `Expanded` under an
          // unbounded main axis throws from inside `performLayout`, which
          // `RenderObject.layout` catches and reports rather than rethrows.
          // The subtree is then left un-laid-out but still mounted, so what
          // the user actually sees is not that error but the cascade behind
          // it: a semantics compile asserting on a child that still needs
          // layout, and a "Cannot hit test a render box with no size" per
          // pointer event for the rest of the page's life.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounded = constraints.hasBoundedWidth;
              final text = Text(
                label,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
                overflow: TextOverflow.ellipsis,
              );
              return Row(
                mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  // Tight under a bounded width, so the label absorbs the
                  // slack and the chevron is pinned to the far edge; loose
                  // under an unbounded one, where there is no slack to absorb
                  // and `Flexible` is the fit `RenderFlex` allows.
                  if (bounded) Expanded(child: text) else Flexible(child: text),
                  const SizedBox(width: 8),
                  FaIcon(
                    open
                        ? FontAwesomeIcons.chevronUp
                        : FontAwesomeIcons.chevronDown,
                    size: 10,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The label's style, and the description's. Shared with
/// [describedDropdownRowHeight], which has to lay the text out in the very
/// styles the row renders in or it is measuring a different paragraph.
TextStyle _dropdownLabelStyle(ThemeConfig theme, {required bool selected}) =>
    TextStyle(
      fontSize: ShellFontSizes.body,
      fontFamily: theme.fontFamily,
      color: selected ? theme.accent : theme.popupForeground,
    );

TextStyle _dropdownDescriptionStyle(ThemeConfig theme) => TextStyle(
  fontSize: ShellFontSizes.caption,
  fontFamily: theme.fontFamily,
  color: theme.popupForeground.withValues(alpha: 0.55),
  height: 1.35,
);

/// One row's *content*; the hover fill, the highlight fill and the tap target
/// are the dropdown's own chrome.
class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({required this.item, required this.selected});

  final SettingsDropdownItem<T> item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final detail = item.detail;
    final description = item.description;
    final label = Row(
      children: [
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _dropdownLabelStyle(theme, selected: selected),
          ),
        ),
        if (detail != null)
          Text(
            detail,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground.withValues(alpha: 0.4),
            ),
          ),
      ],
    );
    if (description == null) return label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: _kDescribedRowGap),
        Text(
          description,
          // The same cap the row extent was measured against: a sentence
          // longer than the card was sized for ellipsises rather than
          // overflowing a fixed-extent row.
          maxLines: _kDescriptionMaxLines,
          overflow: TextOverflow.ellipsis,
          style: _dropdownDescriptionStyle(theme),
        ),
      ],
    );
  }
}

/// Bordered single-line text input backed by [EditableText] (the codebase does
/// not use Material). Seeds its controller once from [initial]; subsequent
/// parent rebuilds do not clobber in-progress edits.
///
/// [leading] and [trailing] are what make this a *search* field as well as a
/// value field — a magnifier before the text, a clear x after it — which is
/// what the file picker's in-folder filter is built from. They live here rather
/// than in a second hand-rolled field for the reason this whole library exists:
/// a control the library lacks gets added to the library.
///
/// [controller] and [focusNode] are for the caller that has to *drive* the
/// field from outside rather than merely read it — the file picker's Ctrl+F
/// focuses and selects it, and Escape clears it. A field handed neither owns
/// its own pair and disposes them; one handed either never disposes what it did
/// not create. Swapping them out across a rebuild is not supported (nothing
/// needs it), so both are resolved once.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    this.initial = '',
    required this.onChanged,
    this.width,
    this.inputFormatters,
    this.hint,
    this.onSubmitted,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.leading,
    this.trailing,
  });

  /// The text the field starts with. Ignored when [controller] is supplied —
  /// a controller carries its own.
  final String initial;

  final ValueChanged<String> onChanged;
  final double? width;
  final List<TextInputFormatter>? inputFormatters;

  /// Placeholder shown while the field is empty.
  ///
  /// [EditableText] has no hint of its own — the shell has no Material — so it
  /// is painted behind the text and driven by the controller, which is why it
  /// costs a [ValueListenableBuilder] rather than a `setState` per keystroke.
  final String? hint;

  /// Enter, for a field whose value is committed rather than merely edited —
  /// the timers composer, where typing a duration and pressing return is the
  /// whole interaction.
  final ValueChanged<String>? onSubmitted;

  /// A controller the caller owns, for a field it also has to clear or select
  /// from outside. Null means the field mints and disposes its own.
  final TextEditingController? controller;

  /// A focus node the caller owns, for a field something else focuses — a
  /// keyboard shortcut, say. Null means the field mints and disposes its own.
  final FocusNode? focusNode;

  final bool autofocus;

  /// Drawn inside the border, before the text.
  final Widget? leading;

  /// Drawn inside the border, after the text.
  final Widget? trailing;

  @override
  _SettingsTextFieldState createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initial);
  late final bool _ownsController = widget.controller == null;
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final bool _ownsFocusNode = widget.focusNode == null;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  // Named rather than a closure so a *borrowed* focus node can be let go of
  // again: a listener left on a node the caller outlives is a setState on a
  // dead element.
  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  /// Kept alive only while focused.
  ///
  /// The settings categories scroll in a lazy `SliverList`, which unmounts a
  /// child far enough past the viewport edge — and this field's
  /// [TextEditingController] reads [SettingsTextField.initial] once, so a
  /// remount would drop the caret and the selection out from under somebody
  /// mid-word. Only while *focused*, because an unfocused field has nothing to
  /// lose that its `initial` does not restore, and a page that kept every field
  /// it had ever shown would be the eager list this replaced.
  ///
  /// The mixin is inert without an `AutomaticKeepAlive` ancestor (which
  /// `SliverList` supplies by default), so a field pumped standalone in a test
  /// behaves exactly as it did.
  @override
  bool get wantKeepAlive => _focused;

  @override
  Widget build(BuildContext context) {
    // Required by AutomaticKeepAliveClientMixin. Omitting it throws in debug.
    super.build(context);
    final theme = ThemeScope.of(context);
    final leading = widget.leading;
    final trailing = widget.trailing;

    final field = Stack(
      children: [
        if (widget.hint != null)
          // Behind the text rather than swapped for it: an IgnorePointer
          // keeps the tap that should focus the field from landing on the
          // placeholder, and painting both means the field never changes
          // height as the first character arrives.
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isNotEmpty
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.hint!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: ShellFontSizes.body,
                            color: theme.popupForeground.withValues(
                              alpha: 0.35,
                            ),
                            fontFamily: theme.fontFamily,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        EditableText(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          style: TextStyle(
            fontSize: ShellFontSizes.body,
            color: theme.popupForeground,
            fontFamily: theme.fontFamily,
          ),
          cursorColor: theme.accent,
          backgroundCursorColor: theme.divider,
          selectionColor: theme.accent.withValues(alpha: 0.4),
          inputFormatters: widget.inputFormatters,
          onChanged: (v) => widget.onChanged(v),
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );

    return Container(
      width: widget.width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(
          color: _focused ? theme.accent : theme.divider,
          width: 1,
        ),
      ),
      child: leading == null && trailing == null
          ? field
          : Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 9)],
                Expanded(child: field),
                if (trailing != null) ...[const SizedBox(width: 6), trailing],
              ],
            ),
    );
  }
}

class SettingsNumberField extends StatelessWidget {
  const SettingsNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isInt,
    this.allowNegative = false,
  });

  final num value;
  final bool isInt;

  /// Whether a minus sign may be typed.
  ///
  /// Off by default because most settings here are a length or a count that
  /// cannot be negative, and the filter is the only thing stopping one. The
  /// shadow offsets and spread are the exception: CSS casts a shadow up and to
  /// the left with negative values, and shrinks one before blurring. A lone
  /// `-` mid-typing parses to null, which the handler below already ignores.
  final bool allowNegative;

  final ValueChanged<num> onChanged;

  /// The four filters, compiled once.
  ///
  /// A `RegExp` compiles its pattern on construction and a
  /// [FilteringTextInputFormatter] is immutable, so building either in `build`
  /// is work charged per rebuild for a value that has four possible answers.
  /// The Modules pane alone carries twenty of these fields.
  static final List<TextInputFormatter> _intOnly = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
  ];
  static final List<TextInputFormatter> _intSigned = [
    FilteringTextInputFormatter.allow(RegExp(r'[-0-9]')),
  ];
  static final List<TextInputFormatter> _decimalOnly = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];
  static final List<TextInputFormatter> _decimalSigned = [
    FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsTextField(
      width: 90,
      initial: isInt ? '${value.toInt()}' : _trimDouble(value.toDouble()),
      inputFormatters: isInt
          ? (allowNegative ? _intSigned : _intOnly)
          : (allowNegative ? _decimalSigned : _decimalOnly),
      onChanged: (text) {
        if (text.isEmpty) return;
        if (isInt) {
          final v = int.tryParse(text);
          if (v != null) onChanged(v);
        } else {
          final v = double.tryParse(text);
          if (v != null) onChanged(v);
        }
      },
    );
  }

  static String _trimDouble(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(1);
    return '$v';
  }
}

/// Parses a `#RRGGBB` / `#AARRGGBB` hex string (`#` optional) into a color.
Color? parseHexColor(String hex) {
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length != 6 && s.length != 8) return null;
  final value = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return value != null ? Color(value) : null;
}

/// A glyph with a box around it, and the box is the target.
///
/// The [box] is what accepts the click, not the glyph: a `FaIcon` is a bare
/// `RichText`, so an icon left to size itself is a target the width of one
/// character. This used to spell its own `MouseRegion` around a
/// `GestureDetector` around a `Container` that painted nothing, which hovered
/// over 26 square and fired over about 11 — see `HoverRegion`, which owns both
/// halves now.
///
/// [color]/[hoverColor] default to the settings pages' dim/accent pair; the
/// clones this replaced (the audio mute toggles, the file picker's hidden-files
/// eye, the notification panel's dismiss x) each carried their own.
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 12,
    this.box = ShellSizes.iconButton,
    this.color,
    this.hoverColor,
    this.enabled = true,
  });

  final FaIconData icon;
  final VoidCallback onTap;
  final double size;

  /// The tap target. [ShellSizes.iconButtonDense] for a row whose height
  /// cannot spare the full box.
  final double box;

  final Color? color;
  final Color? hoverColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      enabled: enabled,
      onTap: onTap,
      builder: (context, hovered) => SizedBox.square(
        dimension: box,
        child: Center(
          child: FaIcon(
            icon,
            size: size,
            color: hovered
                ? (hoverColor ?? theme.accent)
                : (color ?? theme.popupForeground.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Font picker
// ---------------------------------------------------------------------------

/// The height of one row in the font list. Fixed, so the popup can scroll
/// straight to the selected family by arithmetic instead of measuring.
const double _kFontRowHeight = 30;

/// A dropdown of installed font families, each row drawn in its own face.
///
/// [fonts] is supplied by the caller (see `theme/font_catalog.dart`) rather than
/// read here, so widget tests pass a list of three and never fork `fc-list`.
///
/// A thin wrapper over [AnchoredSearchDropdown], which owns the root-overlay
/// float, the filter field, and the keyboard navigation; only the trigger,
/// the ranking, and the rendered-in-its-own-face row live here.
class SettingsFontField extends StatelessWidget {
  const SettingsFontField({
    super.key,
    required this.value,
    required this.fonts,
    required this.onChanged,
    this.locked = false,
    this.onLockedTap,
    this.width = 180,
  });

  final String value;
  final List<String> fonts;
  final ValueChanged<String> onChanged;

  /// Dims the control and routes taps to [onLockedTap] instead of opening the
  /// list. The theme editor uses this for the shipped, read-only themes.
  final bool locked;
  final VoidCallback? onLockedTap;

  final double width;

  @override
  Widget build(BuildContext context) {
    return AnchoredSearchDropdown<String>(
      // Switching themes replaces the value under an open list; leaving it up
      // would let the next click write the old theme's pick into the new one.
      closeKey: value,
      rowHeight: _kFontRowHeight,
      emptyText: 'No matching font',
      filter: (query) {
        final q = query.trim().toLowerCase();
        return q.isEmpty
            ? fonts
            : fonts
                  .where((f) => f.toLowerCase().contains(q))
                  .toList(growable: false);
      },
      // Open highlighted-and-scrolled to the current family rather than at
      // the top of a few hundred rows.
      initialHighlight: (items) => items.indexOf(value),
      onSelected: onChanged,
      itemBuilder: (context, family, highlighted) {
        final theme = ThemeScope.of(context);
        return Text(
          family,
          // The point of the row: what the family actually looks like.
          style: TextStyle(
            fontSize: 13,
            fontFamily: family,
            color: highlighted ? theme.accent : theme.popupForeground,
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
      triggerBuilder: (context, open, toggle) {
        final theme = ThemeScope.of(context);
        return Opacity(
          opacity: locked ? 0.45 : 1.0,
          child: HoverRegion(
            onTap: locked ? (onLockedTap ?? () {}) : toggle,
            builder: (context, hovered) => Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: hovered ? theme.surfaceHover : theme.controlSurface,
                borderRadius: BorderRadius.circular(ShellRadii.control),
                border: Border.all(color: open ? theme.accent : theme.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      // Drawn in the family it names, so the trigger previews
                      // the choice as well as reporting it.
                      style: TextStyle(
                        fontSize: ShellFontSizes.body,
                        fontFamily: value,
                        color: theme.popupForeground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FaIcon(
                    open
                        ? FontAwesomeIcons.chevronUp
                        : FontAwesomeIcons.chevronDown,
                    size: 10,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Colour picker
// ---------------------------------------------------------------------------
//
// Moved here from `shell.dart` when the theme editor stopped being the only
// consumer — same reasoning as the controls above.

/// Formats a color back to the config's hex form: `#RRGGBB` when fully opaque,
/// otherwise `#AARRGGBB`.
String formatHexColor(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = (argb >> 24) & 0xFF;
  if (a == 0xFF) return '#$rgb';
  return '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

/// A color swatch + hex text field. Clicking the swatch opens a visual color
/// picker ([SettingsColorPicker]) floated over the settings window.
class SettingsColorField extends StatefulWidget {
  const SettingsColorField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.locked = false,
    this.onLockedTap,
  });

  final String initial;
  final ValueChanged<String> onChanged;

  /// Dims the field and routes taps to [onLockedTap] instead of opening the
  /// picker. The theme editor uses this for the shipped, read-only themes.
  final bool locked;
  final VoidCallback? onLockedTap;

  @override
  ColorFieldState createState() => ColorFieldState();
}

class ColorFieldState extends State<SettingsColorField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  final _link = LayerLink();
  // The picker floats in the root overlay (not a nearby OverlayPortal target)
  // so a nested Navigator's clipped Overlay can't cut it off. See _open().
  OverlayEntry? _pickerEntry;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode.addListener(
      () => setState(() => _focused = _focusNode.hasFocus),
    );
  }

  @override
  void didUpdateWidget(SettingsColorField old) {
    super.didUpdateWidget(old);
    // Unlike the other controls, this one is re-seeded: switching themes
    // replaces every value under it, and a swatch still showing the previous
    // theme's colour would be a lie.
    //
    // "Did this change come from me?" is answered on the parsed colours, not on
    // the strings: what comes back has been through ThemeConfig.formatColor,
    // whose spelling need not match ours byte for byte, and a re-spelling of
    // the colour we just wrote is not somebody else re-seeding the field. When
    // it was a string compare, every drag inside the picker closed the picker.
    final incoming = parseHexColor(widget.initial);
    final mine = parseHexColor(_controller.text);
    final same = incoming != null && mine != null
        ? incoming == mine
        : widget.initial == _controller.text;
    if (widget.initial != old.initial && !same) {
      _controller.text = widget.initial;
      _close();
    }
  }

  @override
  void dispose() {
    _close();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.locked) {
      widget.onLockedTap?.call();
      return;
    }
    if (_pickerEntry != null) {
      _close();
    } else {
      _open();
    }
  }

  /// The scroll position the swatch sits in, while the picker is open.
  ///
  /// `AnchoredSearchDropdown` states the reasoning: the card is anchored to a
  /// [CompositedTransformTarget] on this row, and the settings categories now
  /// scroll in a lazy `SliverList` that can unmount the row the card is
  /// following.
  ScrollPosition? _hostScroll;

  void _onHostScroll() {
    if (_pickerEntry != null) _close();
  }

  void _open() {
    if (_pickerEntry != null) return;
    // Insert into the root overlay so the picker can extend past the settings
    // content pane (whose nested Navigator Overlay would otherwise clip it).
    final entry = OverlayEntry(builder: (context) => _buildPicker());
    _pickerEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _hostScroll = Scrollable.maybeOf(context)?.position
      ?..isScrollingNotifier.addListener(_onHostScroll);
  }

  void _close() {
    _hostScroll?.isScrollingNotifier.removeListener(_onHostScroll);
    _hostScroll = null;
    _pickerEntry?.remove();
    _pickerEntry = null;
  }

  void _apply(Color color) {
    final hex = formatHexColor(color);
    _controller.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    setState(() {});
    widget.onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final swatch = parseHexColor(_controller.text);
    return Opacity(
      opacity: widget.locked ? 0.45 : 1.0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompositedTransformTarget(
            link: _link,
            child: HoverRegion(
              onTap: _toggle,
              builder: (context, hovered) => Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: swatch ?? const Color(0x00000000),
                  borderRadius: BorderRadius.circular(ShellRadii.barButton),
                  border: Border.all(
                    color: hovered ? theme.accent : theme.divider,
                  ),
                ),
                child: swatch == null
                    ? FaIcon(
                        FontAwesomeIcons.question,
                        size: 10,
                        color: theme.popupForeground.withValues(alpha: 0.4),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 110,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _focused ? theme.accent : theme.divider,
                width: 1,
              ),
            ),
            // Read-only on the main page: the value is edited through the color
            // picker popup, not typed here.
            child: EditableText(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: true,
              style: TextStyle(
                fontSize: 13,
                color: theme.popupForeground,
                fontFamily: theme.fontFamily,
              ),
              cursorColor: theme.accent,
              backgroundCursorColor: theme.divider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker() {
    return Stack(
      children: [
        // Dismiss when tapping outside the popup.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          // The card's own chrome — its padding, border, and the gaps between
          // the sliders — is Padding and DecoratedBox, neither of which
          // hit-tests itself, so a click there used to fall through the Stack
          // to the barrier above and dismiss. A Listener rather than a
          // GestureDetector: it takes the card out of the barrier's hit path
          // without joining the gesture arena, leaving the tap/pan recognizers
          // inside _draggable untouched.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: SettingsColorPicker(
              initial:
                  parseHexColor(_controller.text) ?? const Color(0xFF000000),
              onChanged: _apply,
            ),
          ),
        ),
      ],
    );
  }
}

/// Visual HSV color picker: a draggable saturation/value square, hue and alpha
/// sliders, and a manual hex entry. Emits every change through [onChanged].
class SettingsColorPicker extends StatefulWidget {
  const SettingsColorPicker({required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<SettingsColorPicker> createState() => ColorPickerPopupState();
}

class ColorPickerPopupState extends State<SettingsColorPicker> {
  static const double _w = 200;
  static const double _squareH = 150;
  static const double _sliderH = 14;

  late HSVColor _hsv;
  late final TextEditingController _hexController;
  final _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(
      text: formatHexColor(widget.initial),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// Applies a new HSV value, optionally syncing the hex field text (skipped
  /// while the user is typing into that field).
  void _set(HSVColor hsv, {bool syncHex = true}) {
    _hsv = hsv;
    final color = hsv.toColor();
    if (syncHex) {
      final hex = formatHexColor(color);
      if (_hexController.text != hex) {
        _hexController.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    }
    setState(() {});
    widget.onChanged(color);
  }

  void _onHex(String text) {
    final c = parseHexColor(text);
    if (c != null) _set(HSVColor.fromColor(c), syncHex: false);
  }

  /// A fixed-size region that reports the pointer position (down + drag) as
  /// normalized (0..1) coordinates.
  Widget _draggable({
    required double width,
    required double height,
    required ValueChanged<Offset> onChange,
    required Widget child,
  }) {
    void handle(Offset local) {
      onChange(
        Offset(
          (local.dx / width).clamp(0.0, 1.0),
          (local.dy / height).clamp(0.0, 1.0),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => handle(d.localPosition),
      onPanDown: (d) => handle(d.localPosition),
      onPanUpdate: (d) => handle(d.localPosition),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = _hsv.toColor();
    return PopupTransition(
      child: Container(
        width: _w + 24,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Opaque inside the settings page — this card covers the swatch row
          // it is editing. See [OpaquePopupScope].
          color: OpaquePopupScope.fill(context, theme),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.accent, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Saturation / value square.
            _draggable(
              width: _w,
              height: _squareH,
              onChange: (n) =>
                  _set(_hsv.withSaturation(n.dx).withValue(1 - n.dy)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  painter: _SVPainter(_hsv.hue),
                  foregroundPainter: _SVCursorPainter(
                    saturation: _hsv.saturation,
                    value: _hsv.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Hue slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) =>
                  _set(_hsv.withHue((n.dx * 360).clamp(0.0, 360.0))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _HuePainter(),
                  foregroundPainter: _ThumbPainter(_hsv.hue / 360),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Alpha slider.
            _draggable(
              width: _w,
              height: _sliderH,
              onChange: (n) => _set(_hsv.withAlpha(n.dx)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_sliderH / 2),
                child: CustomPaint(
                  painter: _AlphaPainter(_hsv.withAlpha(1).toColor()),
                  foregroundPainter: _ThumbPainter(_hsv.alpha),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Manual hex entry.
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.divider),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.workspaceBackground,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.divider),
                    ),
                    child: EditableText(
                      controller: _hexController,
                      focusNode: _hexFocus,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.popupForeground,
                        fontFamily: theme.fontFamily,
                      ),
                      cursorColor: theme.accent,
                      backgroundCursorColor: theme.divider,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]'),
                        ),
                      ],
                      onChanged: _onHex,
                    ),
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

/// Paints the saturation (x) / value (y) gradient field for a given [hue].
class _SVPainter extends CustomPainter {
  _SVPainter(this.hue);

  final double hue;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [const Color(0xFFFFFFFF), hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.hue != hue;
}

/// Draws the ring cursor over the saturation/value square.
class _SVCursorPainter extends CustomPainter {
  _SVCursorPainter({required this.saturation, required this.value});

  final double saturation;
  final double value;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final c = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      c,
      6,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      c,
      7.5,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x88000000),
    );
  }

  @override
  bool shouldRepaint(_SVCursorPainter old) =>
      old.saturation != saturation || old.value != value;
}

/// Paints the full hue spectrum bar.
class _HuePainter extends CustomPainter {
  @override
  void paint(ui.Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => false;
}

/// Paints the alpha slider: a checkerboard behind a transparent→opaque gradient
/// of the current [color].
class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.color);

  final Color color;

  @override
  void paint(ui.Canvas canvas, Size size) {
    const cell = 5.0;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, ui.Paint()..color = const Color(0xFFCCCCCC));
    final dark = ui.Paint()..color = const Color(0xFF888888);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter old) => old.color != color;
}

/// Draws the round thumb for the hue/alpha sliders at normalized position [t].
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.t);

  final double t;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final r = size.height / 2;
    final x = (t.clamp(0.0, 1.0) * size.width).clamp(r, size.width - r);
    final center = Offset(x, size.height / 2);
    canvas.drawCircle(
      center,
      r - 1,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Confirmation
// ---------------------------------------------------------------------------

/// A modal "are you sure?" card for a destructive settings action.
///
/// A scrim plus a [PopupCard] rather than a Material dialog, which the shell
/// does not use anywhere; this is the same shape as `KillConfirm` in
/// `overlay/system/kill_confirm.dart`, generalized so the settings panes do not
/// grow a third hand-rolled copy. The one thing it does not take from the theme
/// is its rim: the accent border marks a destructive action, so it overrides
/// `popup_border` rather than following it.
///
/// [warning] is a second paragraph for a consequence the user cannot see from
/// the row they clicked — removing the last panel, say. Null when there is
/// none, so the card does not carry an empty line.
class SettingsConfirmCard extends StatelessWidget {
  const SettingsConfirmCard({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.warning,
  });

  final String title;
  final String message;
  final String? warning;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final warning = this.warning;
    return Focus(
      autofocus: true,
      // Escape cancels, matching the power menu's confirmation
      // (`modules/system.dart`). The card is modal, so nothing below it is
      // competing for the key.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Tapping the scrim cancels, which is the least surprising thing a
          // click outside a confirmation can do.
          Positioned.fill(
            child: GestureDetector(
              onTap: onCancel,
              child: Container(color: const Color(0x99000000)),
            ),
          ),
          Center(
            child: SizedBox(
              width: 380,
              child: PopupCard(
                border: Border.all(color: theme.accent, width: 1.5),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        height: 1.4,
                        color: theme.popupForeground.withValues(alpha: 0.7),
                      ),
                    ),
                    if (warning != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          warning,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: theme.fontFamily,
                            height: 1.4,
                            color: theme.popupForeground.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SettingsOptionButton(
                          label: 'Cancel',
                          selected: false,
                          onTap: onCancel,
                        ),
                        const SizedBox(width: 8),
                        SettingsOptionButton(
                          label: confirmLabel,
                          selected: true,
                          onTap: onConfirm,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a [SettingsConfirmCard] in the nearest *root* [Overlay], resolving to
/// true if the user confirmed and false if they cancelled or dismissed it.
///
/// The root overlay for the same reason [SettingsColorField]'s picker uses one:
/// the Shell settings pane is a nested `Navigator`, and a scrim inserted into
/// its overlay — or built into a scrolled section — would cover the pane's
/// content while leaving the sidebar and header live. Cloned from
/// `showAppChooser` in `desktop/app_chooser.dart`.
Future<bool> showSettingsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? warning,
}) {
  return showRootModal<bool>(
    context,
    (close) => SettingsConfirmCard(
      title: title,
      message: message,
      warning: warning,
      confirmLabel: confirmLabel,
      onCancel: () => close(false),
      onConfirm: () => close(true),
    ),
  );
}

/// Editable ordered list of strings. When [suggestions] is provided, new items
/// are added from a dropdown of those values; otherwise a free-form text field
/// is revealed. Existing items can be reordered and removed.
///
/// The adder is a [SettingsAddButton] on the list's heading row, never a
/// control under the rows: an adder below the list moves down the pane every
/// time the user uses it, and a panel's third module slot pushed it off the
/// bottom of the scroll view entirely. The free-form flavour keeps its text
/// field — a value nothing can rank has to be typed — but the button is what
/// reveals it, so both flavours are the same button in the same place.
class SettingsStringListEditor extends StatefulWidget {
  const SettingsStringListEditor({
    super.key,
    required this.items,
    required this.onChanged,
    this.label,
    this.addLabel,
    this.suggestions,
    this.addHint,
    this.width = 260,
  });

  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  /// Heading rendered over the list, with the add button on its right. Null
  /// where the list is already the control of a labelled [SettingsRow] — the
  /// button then sits alone at the top right of the editor's own column.
  final String? label;

  /// Text on the add button. Defaults to a bare "Add".
  final String? addLabel;

  final List<String>? suggestions;
  final String? addHint;

  /// Fixed editor width. Pass `null` to stretch to the parent's width (used on
  /// the Panels page, where the list sits full-width under its label).
  final double? width;

  @override
  State<SettingsStringListEditor> createState() =>
      _SettingsStringListEditorState();
}

class _SettingsStringListEditorState extends State<SettingsStringListEditor> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  /// Whether the free-form adder's field is showing. Always false when
  /// [SettingsStringListEditor.suggestions] is set — that flavour adds from a
  /// dropdown and has no field to reveal.
  bool _composing = false;

  @override
  void initState() {
    super.initState();
    _addFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _toggleComposer() {
    if (_composing) {
      _closeComposer();
      return;
    }
    setState(() => _composing = true);
    _addFocus.requestFocus();
  }

  void _closeComposer() {
    setState(() {
      _composing = false;
      _addController.clear();
    });
  }

  void _emit(List<String> list) => widget.onChanged(list);

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    _emit([...widget.items, v]);
  }

  void _removeAt(int i) {
    final list = [...widget.items]..removeAt(i);
    _emit(list);
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= widget.items.length) return;
    final list = [...widget.items];
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
    _emit(list);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final button = _buildAddButton(context);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          SettingsSubLabel(label, trailing: button)
        else
          // No heading to hang it on: the button still goes to the top right
          // of the editor's own column, above the rows' icons.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(alignment: Alignment.centerRight, child: button),
          ),
        if (label != null) const SizedBox(height: 6),
        if (_composing) ...[_buildComposer(context), const SizedBox(height: 6)],
        if (widget.items.isEmpty && !_composing)
          const SettingsHint('Nothing here yet.')
        else
          for (var i = 0; i < widget.items.length; i++)
            _row(context, i, widget.items[i]),
      ],
    );
    final width = widget.width;
    return width == null ? column : SizedBox(width: width, child: column);
  }

  Widget _row(BuildContext context, int i, String item) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronUp,
              size: 10,
              onTap: () => _move(i, -1),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.chevronDown,
              size: 10,
              onTap: () => _move(i, 1),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.xmark,
              size: 12,
              onTap: () => _removeAt(i),
            ),
          ],
        ),
      ),
    );
  }

  /// The list's add action: the dropdown trigger when there are suggestions
  /// to rank, and otherwise the toggle that reveals [_buildComposer].
  Widget _buildAddButton(BuildContext context) {
    final suggestions = widget.suggestions;
    if (suggestions != null) {
      return _AddDropdown(
        label: widget.addLabel ?? 'Add',
        options: suggestions,
        onSelected: _add,
      );
    }
    return SettingsAddButton(
      label: widget.addLabel ?? 'Add',
      onTap: _toggleComposer,
    );
  }

  /// The free-form adder's field, revealed under the heading by the add
  /// button. Above the rows rather than below them, so it stays put as the
  /// list grows under it — the whole reason the button moved up here.
  Widget _buildComposer(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.popupBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _addFocus.hasFocus ? theme.accent : theme.divider,
              ),
            ),
            child: Stack(
              children: [
                if (_addController.text.isEmpty)
                  Text(
                    widget.addHint ?? 'add…',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.popupForeground.withValues(alpha: 0.35),
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                EditableText(
                  controller: _addController,
                  focusNode: _addFocus,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.popupForeground,
                    fontFamily: theme.fontFamily,
                  ),
                  cursorColor: theme.accent,
                  backgroundCursorColor: theme.divider,
                  onChanged: (_) => setState(() {}),
                  // Enter commits and leaves the field open and focused: these
                  // lists are typed in runs (a handful of tray ids, a handful
                  // of dock apps), so closing after each one would mean a
                  // click on the button between every two entries.
                  onSubmitted: (v) {
                    _add(v);
                    _addController.clear();
                    setState(() {});
                    _addFocus.requestFocus();
                  },
                ),
              ],
            ),
          ),
        ),
        SettingsIconButton(
          icon: FontAwesomeIcons.check,
          onTap: () {
            _add(_addController.text);
            _addController.clear();
            setState(() {});
            _addFocus.requestFocus();
          },
        ),
        SettingsIconButton(icon: FontAwesomeIcons.xmark, onTap: _closeComposer),
      ],
    );
  }
}

/// The string-list editor's adder: a plus button that drops the [options] over
/// the pane, through the same [AnchoredSearchDropdown] every other selector in
/// the settings UI now uses.
///
/// It expanded inline until this — the module list is a dozen-odd rows, so
/// opening it shoved the panel's own module slots off the bottom of the pane
/// that the user was picking a module *for*.
class _AddDropdown extends StatelessWidget {
  const _AddDropdown({
    required this.label,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return AnchoredSearchDropdown<String>(
      // Right-aligned rather than trigger-width: the button is now a compact
      // action on the list's heading row, so a card sized to it would be too
      // narrow to read a module name in, and one hanging left-to-right off it
      // would run past the pane. It grows leftwards from the button's edge.
      alignRight: true,
      rowHeight: 30,
      maxHeight: 260,
      emptyText: 'No matching module',
      filter: (query) {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options
            .where((o) => o.toLowerCase().contains(q))
            .toList(growable: false);
      },
      onSelected: onSelected,
      itemBuilder: (context, option, _) {
        final theme = ThemeScope.of(context);
        return Text(
          option,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground,
          ),
        );
      },
      triggerBuilder: (context, open, toggle) =>
          SettingsAddButton(label: label, onTap: toggle),
    );
  }
}

/// A plus-labelled button for appending to a collection: the string-list
/// editor's dropdown toggle, and the Background and Desktop sections' add
/// actions.
///
/// Sized to sit on a [SettingsSubLabel]'s heading row rather than as a block
/// under a list — that is where all of these now live — so its box comes out
/// at [ShellSizes.iconButton]'s height, lining up with the column of row icons
/// below it and staying clear of [ShellSizes.minTapTarget].
class SettingsAddButton extends StatelessWidget {
  const SettingsAddButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : theme.controlSurface,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(color: theme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.plus,
              size: ShellFontSizes.caption,
              color: hovered ? theme.popupForeground : theme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
