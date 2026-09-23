// Window Manager > Animations: whether miracle animates at all, and what each
// of its animateable events looks like when it does.
//
// The set of events is the compositor's, not the configuration's — miracle
// fixes it, so the list here can neither grow nor shrink and every row is an
// event that exists. What is editable is how long each one runs and which
// concurrent movements it is built from.
//
// Everything below addresses an event by its *index* and re-reads it from the
// store inside the callback, never through an `AnimateableEvent` captured at
// build time. Such an object holds the configuration it came from, and
// `MiracleConfigStore.reset` frees that tree — so a captured one is a
// `StateError` waiting for the frame between the reset and the rebuild.

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:moonswing/miracle_config/miracle_config_store.dart';
import 'package:moonswing/miracle_config/miracle_labels.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/miracle/miracle_controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// What "Add animation" adds.
///
/// A fade on a linear curve: the one combination that is visible whatever the
/// event is and whatever the other parts are doing, so a part somebody has just
/// added is a part they can see.
const BuiltInAnimation _kNewPart = BuiltInAnimation(
  type: AnimationType.fade,
  function: EaseFunction.linear,
);

final List<SettingsDropdownItem<AnimationType>> _typeItems = [
  for (final type in AnimationType.values)
    SettingsDropdownItem(value: type, label: animationTypeLabel(type)),
];

final List<SettingsDropdownItem<EaseFunction>> _easeItems = [
  for (final function in EaseFunction.values)
    SettingsDropdownItem(
      value: function,
      label: easeFunctionLabel(function),
      detail: function.wireName,
    ),
];

/// One easing coefficient: its name, how to read it, how to write it.
typedef _Coefficient = (
  String name,
  double Function(BuiltInAnimation animation) read,
  BuiltInAnimation Function(BuiltInAnimation animation, double value) write,
);

/// The seven coefficients, as reader/writer pairs.
///
/// A table rather than seven near-identical fields, for `gaps_borders.dart`'s
/// reason: spelling the same control seven times is seven chances to wire one
/// of them to its neighbour's setter.
const List<_Coefficient> _kCoefficients = [
  ('c1', _c1, _setC1),
  ('c2', _c2, _setC2),
  ('c3', _c3, _setC3),
  ('c4', _c4, _setC4),
  ('c5', _c5, _setC5),
  ('n1', _n1, _setN1),
  ('d1', _d1, _setD1),
];

double _c1(BuiltInAnimation a) => a.c1;
double _c2(BuiltInAnimation a) => a.c2;
double _c3(BuiltInAnimation a) => a.c3;
double _c4(BuiltInAnimation a) => a.c4;
double _c5(BuiltInAnimation a) => a.c5;
double _n1(BuiltInAnimation a) => a.n1;
double _d1(BuiltInAnimation a) => a.d1;

BuiltInAnimation _setC1(BuiltInAnimation a, double v) => a.copyWith(c1: v);
BuiltInAnimation _setC2(BuiltInAnimation a, double v) => a.copyWith(c2: v);
BuiltInAnimation _setC3(BuiltInAnimation a, double v) => a.copyWith(c3: v);
BuiltInAnimation _setC4(BuiltInAnimation a, double v) => a.copyWith(c4: v);
BuiltInAnimation _setC5(BuiltInAnimation a, double v) => a.copyWith(c5: v);
BuiltInAnimation _setN1(BuiltInAnimation a, double v) => a.copyWith(n1: v);
BuiltInAnimation _setD1(BuiltInAnimation a, double v) => a.copyWith(d1: v);

class MiracleAnimationsSection extends StatelessWidget {
  const MiracleAnimationsSection({super.key, required this.store});

  final MiracleConfigStore store;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Animations',
          info: 'Events keep their settings while animations are off.',
          children: [
            SettingsRow.field(
              SettingsCatalog.miracleAnimationsEnabled,
              control: MiracleValue<bool>(
                store: store,
                select: (config) => config.animationsEnabled,
                fallback: true,
                builder: (context, value) => SettingsToggle(
                  value: value,
                  onChanged: (next) =>
                      store.edit((config) => config.animationsEnabled = next),
                ),
              ),
            ),
          ],
        ),
        SliverSettingsSection(
          label: 'Events',
          info: SettingsCatalog.miracleAnimatedEvents.description,
          children: [
            MiracleCollection(
              store: store,
              signature: _eventsSignature,
              builder: (context, config) {
                final events = config.animateableEvents;
                if (events.isEmpty) {
                  return const SettingsHint(
                    'This build of miracle reports no animateable events.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < events.length; i++)
                      _EventCard(
                        // See `MiracleConfigStore.editStructure`: adding or
                        // removing a part shifts every field below it.
                        key: ValueKey('event:${store.structureRevision}:$i'),
                        store: store,
                        index: i,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({super.key, required this.store, required this.index});

  final MiracleConfigStore store;
  final int index;

  /// Runs [body] against the event as the store holds it *now*.
  void _withEvent(void Function(AnimateableEvent event) body, {
    bool structural = false,
  }) {
    void mutate(MiracleConfig config) {
      final events = config.animateableEvents;
      if (index >= events.length) return;
      body(events[index]);
    }

    if (structural) {
      store.editStructure(mutate);
    } else {
      store.edit(mutate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final config = store.config;
    if (config == null || index >= config.animateableEvents.length) {
      return const SizedBox.shrink();
    }
    final event = config.animateableEvents[index];
    final parts = event.parts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(color: theme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    animateableEventLabel(event.name),
                    style: TextStyle(
                      fontSize: ShellFontSizes.body,
                      fontFamily: theme.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: theme.popupForeground,
                    ),
                  ),
                ),
                // Only where there is something to restore. `isDefault` is
                // miracle's own answer to "has the user touched this", so the
                // button appears exactly when it would do something.
                if (!event.isDefault) ...[
                  SettingsActionButton(
                    label: 'Restore default',
                    compact: true,
                    onTap: () =>
                        _withEvent((event) => event.reset(), structural: true),
                  ),
                  const SizedBox(width: 8),
                ],
                SettingsAddButton(
                  label: 'Add animation',
                  onTap: () => _withEvent(
                    (event) => event.parts.add(_kNewPart),
                    structural: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsRow(
              label: 'Duration (seconds)',
              control: SettingsNumberField(
                value: event.durationSeconds,
                isInt: false,
                onChanged: (next) => _withEvent(
                  (event) => event.durationSeconds = next.toDouble(),
                ),
              ),
            ),
            if (parts.isEmpty)
              const SettingsHint(
                'No animations, so this event happens instantly however long '
                'the duration says.',
              )
            else
              for (var i = 0; i < parts.length; i++)
                _PartCard(
                  part: parts[i],
                  onChanged: (next) => _withEvent((event) {
                    final parts = event.parts;
                    if (i >= parts.length) return;
                    parts[i] = next;
                  }),
                  onRemove: () => _withEvent(
                    (event) {
                      if (i >= event.parts.length) return;
                      event.parts.removeAt(i);
                    },
                    structural: true,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.part,
    required this.onChanged,
    required this.onRemove,
  });

  final BuiltInAnimation part;
  final ValueChanged<BuiltInAnimation> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return SettingsListRow(
      onRemove: onRemove,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SettingsDropdown<AnimationType>(
                  items: _typeItems,
                  selected: part.type,
                  onSelected: (next) => onChanged(part.copyWith(type: next)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SettingsDropdown<EaseFunction>(
                  items: _easeItems,
                  selected: part.function,
                  onSelected: (next) =>
                      onChanged(part.copyWith(function: next)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Easing coefficients',
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 4),
              const SettingsInfoTip(
                'Most curves ignore these. easings.net shows what each curve '
                'does with them.',
              ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final (name, read, write) in _kCoefficients)
                _CoefficientField(
                  label: name,
                  value: read(part),
                  // Every one of these can legitimately be negative: an
                  // overshooting curve is written with one.
                  onChanged: (next) => onChanged(write(part, next)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoefficientField extends StatelessWidget {
  const _CoefficientField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 4),
        SettingsNumberField(
          value: value,
          isInt: false,
          allowNegative: true,
          onChanged: (next) => onChanged(next.toDouble()),
        ),
      ],
    );
  }
}

/// Everything the event editor renders, as one string.
String _eventsSignature(MiracleConfig config) => [
  for (final event in config.animateableEvents)
    '${event.name}|${event.durationSeconds}|${event.isDefault}|'
        '${_partsSignature(event)}',
].join('\n');

String _partsSignature(AnimateableEvent event) => [
  for (final part in event.parts)
    '${part.type.value}:${part.function.value}:${part.c1}:${part.c2}:'
        '${part.c3}:${part.c4}:${part.c5}:${part.n1}:${part.d1}',
].join(';');
