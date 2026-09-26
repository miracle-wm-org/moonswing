// The components Claude may build a UI out of, drawn by the shell.
//
// genui ships a basic catalogue, and every widget in it is Material — an
// `ElevatedButton`, a `CheckboxListTile`, a `Card` in `ColorScheme.surface` —
// in a shell that has no Material theme and paints every control out of
// `ThemeScope`. So this catalogue keeps genui's *vocabulary* and replaces its
// *pictures*: each item here takes the basic item's name and data schema
// verbatim, so the A2UI Claude writes is exactly what genui's own prompt and
// validator describe, and renders it with the controls Settings is built from
// (`overlay/settings/controls.dart`). The three pure layout items — Column,
// Row, List — draw nothing of their own and are genui's, unchanged.
//
// What is left out is left out on purpose. Image, Video and AudioPlayer would
// have the shell fetching whatever URL a model wrote into a component; Modal
// and Tabs are navigation inside a card that is already a popup; the date
// picker is Material through and through. Claude is told what exists by the
// catalogue's own schema, so an omitted item is one it never asks for.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/audio/audio_slider.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The id Claude is told to create surfaces against.
const String kClaudeCatalogId = 'org.moonswing.claude.catalog';

/// How the shell's controls are to be used, said once in the system prompt.
const String _catalogRules = '''
The UI is shown inside a small popup card on a Linux desktop, about 440 pixels
wide, in the user's own theme. Keep generated UIs compact: a heading, a few
controls, and a button that sends the result back. Prefer a single Column as
the root. Every interactive control should bind its value to the data model
with a "path" so that a button's action context can send it back to you.
''';

/// The catalogue.
Catalog claudeShellCatalog() => Catalog(
  [
    BasicCatalogItems.column,
    BasicCatalogItems.row,
    BasicCatalogItems.list,
    _text,
    _button,
    _card,
    _divider,
    _checkBox,
    _textField,
    _slider,
    _choicePicker,
  ],
  functions: BasicFunctions.all,
  catalogId: kClaudeCatalogId,
  systemPromptFragments: [BasicCatalogItems.basicCatalogRules, _catalogRules],
);

/// The `path` a component's value is bound to, or [fallback] for a literal.
String _pathOf(Object? ref, String fallback) =>
    ref is Map && ref['path'] is String ? ref['path'] as String : fallback;

/// Resolves an action's event and hands it to genui. Function-call actions are
/// genui's client functions (`openUrl`, formatting, …); those are run through
/// the data context like the basic catalogue does.
Future<void> _runAction(CatalogItemContext item, Object? action) async {
  if (action is! Map) return;
  final event = action['event'];
  if (event is Map && event['name'] is String) {
    final context = event['context'];
    final resolved = await resolveContext(
      item.dataContext,
      context is Map<String, Object?> ? context : null,
    );
    item.dispatchEvent(
      UserActionEvent(
        name: event['name'] as String,
        sourceComponentId: item.id,
        context: resolved,
      ),
    );
    return;
  }
  final call = action['functionCall'];
  if (call is Map<String, Object?>) {
    try {
      await item.dataContext
          .resolve(call)
          .first
          .timeout(const Duration(seconds: 10));
    } catch (e, stack) {
      item.reportError(
        A2uiFunctionException(
          'Function execution failed.',
          functionName: '${call['call']}',
          cause: e,
        ),
        stack,
      );
    }
  }
}

// --- Text ------------------------------------------------------------------

final CatalogItem _text = CatalogItem(
  name: 'Text',
  dataSchema: BasicCatalogItems.text.dataSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final variant = data['variant'] as String? ?? 'body';
    return BoundString(
      dataContext: item.dataContext,
      value: data['text'],
      builder: (context, value) {
        final theme = ThemeScope.of(context);
        final (size, weight, alpha) = switch (variant) {
          'h1' => (ShellFontSizes.heading, FontWeight.w700, 1.0),
          'h2' => (ShellFontSizes.title, FontWeight.w700, 1.0),
          'h3' || 'h4' => (ShellFontSizes.label, FontWeight.w600, 1.0),
          'h5' => (ShellFontSizes.body, FontWeight.w600, 1.0),
          'caption' => (ShellFontSizes.caption, FontWeight.w400, 0.6),
          _ => (ShellFontSizes.body, FontWeight.w400, 1.0),
        };
        return Text(
          // Markdown emphasis markers are dropped rather than rendered: the
          // shell has no markdown renderer, and `**` on screen is noise.
          (value ?? '').replaceAll('**', ''),
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            height: 1.4,
            color: theme.popupForeground.withValues(alpha: alpha),
          ),
        );
      },
    );
  },
);

// --- Button ----------------------------------------------------------------

final CatalogItem _button = CatalogItem(
  name: 'Button',
  dataSchema: BasicCatalogItems.button.dataSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final child = data['child'];
    final variant = data['variant'] as String? ?? '';
    final checks = (data['checks'] as List?)?.cast<JsonMap>();
    return StreamBuilder<String?>(
      stream: ValidationHelper.validateStream(checks, item.dataContext),
      builder: (context, snapshot) => _ShellButton(
        primary: variant == 'primary',
        borderless: variant == 'borderless',
        enabled: snapshot.data == null,
        onTap: () => _runAction(item, data['action']),
        child: child is String ? item.buildChild(child) : const SizedBox(),
      ),
    );
  },
);

/// A button around a child component — the basic catalogue's `Button` takes a
/// component, usually a `Text`, rather than a label, which is why this is not
/// [SettingsActionButton]. Styled to match it.
class _ShellButton extends StatelessWidget {
  const _ShellButton({
    required this.primary,
    required this.borderless,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool primary;
  final bool borderless;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final foreground = primary ? kOnAccent : theme.popupForeground;
    return RepaintBoundary(
      child: HoverRegion(
        enabled: enabled,
        onTap: onTap,
        builder: (context, hovered) => Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: ShellSizes.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary
                  ? (hovered
                        ? theme.accent.withValues(alpha: 0.85)
                        : theme.accent)
                  : hovered
                  ? theme.surfaceHover
                  : borderless
                  ? const Color(0x00000000)
                  : theme.popupForeground.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: borderless || primary
                  ? null
                  : Border.all(color: theme.divider),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground, fontWeight: FontWeight.w500),
              // A `Text` component paints its own colour; the override keeps a
              // primary button's label readable on the accent.
              child: primary
                  ? ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        foreground,
                        BlendMode.srcIn,
                      ),
                      child: child,
                    )
                  : child,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Card, Divider ---------------------------------------------------------

final CatalogItem _card = CatalogItem(
  name: 'Card',
  dataSchema: BasicCatalogItems.card.dataSchema,
  widgetBuilder: (item) {
    final child = (item.data as JsonMap)['child'];
    return Builder(
      builder: (context) {
        final theme = ThemeScope.of(context);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.popupForeground.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(ShellRadii.control),
            border: Border.all(color: theme.divider),
          ),
          child: child is String ? item.buildChild(child) : null,
        );
      },
    );
  },
);

final CatalogItem _divider = CatalogItem(
  name: 'Divider',
  dataSchema: BasicCatalogItems.divider.dataSchema,
  widgetBuilder: (item) {
    final vertical = (item.data as JsonMap)['axis'] == 'vertical';
    return Builder(
      builder: (context) {
        final color = ThemeScope.of(context).divider;
        return vertical
            ? Container(width: 1, color: color)
            : Container(height: 1, color: color);
      },
    );
  },
);

// --- CheckBox --------------------------------------------------------------

final CatalogItem _checkBox = CatalogItem(
  name: 'CheckBox',
  dataSchema: BasicCatalogItems.checkBox.dataSchema,
  isImplicitlyFlexible: true,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final path = _pathOf(data['value'], '${item.id}.value');
    return BoundString(
      dataContext: item.dataContext,
      value: data['label'],
      builder: (context, label) => BoundBool(
        dataContext: item.dataContext,
        value: {'path': path},
        builder: (context, value) => Row(
          children: [
            Expanded(child: Text(label ?? '')),
            const SizedBox(width: 12),
            SettingsToggle(
              value:
                  value ??
                  (data['value'] is bool ? data['value'] as bool : false),
              onChanged: (v) => item.dataContext.update(DataPath(path), v),
            ),
          ],
        ),
      ),
    );
  },
);

// --- TextField -------------------------------------------------------------

final CatalogItem _textField = CatalogItem(
  name: 'TextField',
  dataSchema: BasicCatalogItems.textField.dataSchema,
  isImplicitlyFlexible: true,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final valueRef = data['value'];
    final path = _pathOf(valueRef, '${item.id}.value');
    final variant = data['variant'] as String? ?? 'shortText';
    return BoundString(
      dataContext: item.dataContext,
      value: data['label'],
      builder: (context, label) {
        return SettingsTextField(
          // Seeded once, as every `SettingsTextField` is: the data model is
          // written on every keystroke, and re-seeding from it would fight
          // the caret.
          initial: valueRef is String ? valueRef : '',
          hint: label,
          obscureText: variant == 'obscured',
          maxLines: variant == 'longText' ? 6 : 1,
          minLines: variant == 'longText' ? 3 : null,
          inputFormatters: variant == 'number'
              ? [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))]
              : null,
          onChanged: (text) {
            final number = variant == 'number' ? num.tryParse(text) : null;
            item.dataContext.update(DataPath(path), number ?? text);
          },
          onSubmitted: data['onSubmittedAction'] == null
              ? null
              : (_) => _runAction(item, data['onSubmittedAction']),
        );
      },
    );
  },
);

// --- Slider ----------------------------------------------------------------

final CatalogItem _slider = CatalogItem(
  name: 'Slider',
  dataSchema: BasicCatalogItems.slider.dataSchema,
  isImplicitlyFlexible: true,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final min = (data['min'] as num?)?.toDouble() ?? 0.0;
    var max = (data['max'] as num?)?.toDouble() ?? 1.0;
    if (max <= min) max = min + 1;
    final path = _pathOf(data['value'], '${item.id}.value');
    final integral = min == min.roundToDouble() && max - min >= 5;
    return BoundString(
      dataContext: item.dataContext,
      value: data['label'],
      builder: (context, label) => BoundNumber(
        dataContext: item.dataContext,
        value: {'path': path},
        builder: (context, value) {
          final literal = data['value'] is num
              ? (data['value'] as num).toDouble()
              : min;
          final v = (value?.toDouble() ?? literal).clamp(min, max);
          final shown = integral ? v.round().toString() : v.toStringAsFixed(2);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label ?? '')),
                  Text(shown),
                ],
              ),
              const SizedBox(height: 4),
              AudioSlider(
                value: v,
                min: min,
                max: max,
                onChanged: (next) => item.dataContext.update(
                  DataPath(path),
                  integral ? next.roundToDouble() : next,
                ),
                onChangeEnd: (_) {},
              ),
            ],
          );
        },
      ),
    );
  },
);

// --- ChoicePicker ----------------------------------------------------------

final CatalogItem _choicePicker = CatalogItem(
  name: 'ChoicePicker',
  dataSchema: BasicCatalogItems.choicePicker.dataSchema,
  widgetBuilder: (item) {
    final data = item.data as JsonMap;
    final exclusive = data['variant'] == 'mutuallyExclusive';
    final valueRef = data['value'];
    final path = _pathOf(valueRef, '${item.id}.value');
    return BoundString(
      dataContext: item.dataContext,
      value: data['label'],
      builder: (context, label) => BoundList(
        dataContext: item.dataContext,
        value: data['options'],
        builder: (context, rawOptions) => BoundObject(
          dataContext: item.dataContext,
          value: {'path': path},
          builder: (context, current) {
            final options = _options(rawOptions ?? const []);
            final selected = _selection(current ?? valueRef);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((label ?? '').isNotEmpty) ...[
                  Text(label!),
                  const SizedBox(height: 6),
                ],
                SettingsChipToggles<String>(
                  alignment: WrapAlignment.start,
                  options: [for (final o in options) o.$1],
                  selected: selected,
                  labelOf: (v) => options
                      .firstWhere((o) => o.$1 == v, orElse: () => (v, v))
                      .$2,
                  onChanged: (next) {
                    final List<String> value;
                    if (exclusive) {
                      final added = next.difference(selected);
                      value = added.isEmpty ? [] : [added.first];
                    } else {
                      value = [
                        for (final o in options)
                          if (next.contains(o.$1)) o.$1,
                      ];
                    }
                    item.dataContext.update(DataPath(path), value);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  },
);

/// `(value, label)` for each well-formed option. A label bound to the data
/// model is shown as its value — the picker is not worth a subscription per
/// chip — and a malformed option costs that option.
List<(String, String)> _options(List<Object?> raw) => [
  for (final o in raw)
    if (o is Map && o['value'] != null)
      (
        '${o['value']}',
        o['label'] is String ? o['label'] as String : '${o['value']}',
      ),
];

Set<String> _selection(Object? value) => switch (value) {
  final List<Object?> list => {for (final v in list) '$v'},
  final String single => {single},
  _ => const {},
};
