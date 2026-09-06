// The subscription seams and the two or three shapes every Window Manager
// section repeats.
//
// `ConfigValue` cannot serve here: it reads a `config.toml` path out of
// `ConfigStore`, and miracle's configuration is a native tree behind seventy
// typed getters. What carries over is the *rule* — the store notifies on every
// edit anywhere in the pane, so a section-wide `ListenableBuilder` would rebuild
// twenty rows for one digit typed into one of them. [MiracleValue] is
// `StoreSelector` specialised to that tree, and it is what every control on
// these pages is wrapped in.
library;

import 'package:flutter/widgets.dart';

import 'package:miracle/miracle.dart';

import 'package:graceful_shell/miracle_config/miracle_config_store.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The width a Window Manager row gives its control.
///
/// Fixed, for [SettingsDropdown]'s reason in `shell/power.dart`: a row sizes its
/// control to itself, so an unconstrained trigger is as wide as whichever option
/// happens to be selected and resizes every time the user picks another.
const double kMiracleControlWidth = 240;

/// One value out of the loaded configuration, and only the widgets that render
/// it.
///
/// [fallback] is what the builder is handed while nothing is loaded. In practice
/// the pane does not build a section without a configuration; the fallback is
/// what keeps a control that is mid-teardown from dereferencing a freed tree
/// during a [MiracleConfigStore.reset].
class MiracleValue<T> extends StatelessWidget {
  const MiracleValue({
    super.key,
    required this.store,
    required this.select,
    required this.fallback,
    required this.builder,
  });

  final MiracleConfigStore store;

  /// Reads the one value this widget renders. Called on every notify, so keep
  /// it to the getter — these are FFI calls, not computations.
  final T Function(MiracleConfig config) select;

  final T fallback;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) => StoreSelector<T>(
    listenable: store,
    selector: () {
      final config = store.config;
      return config == null ? fallback : select(config);
    },
    builder: builder,
  );
}

/// One of the configuration's *collections*, and only the widgets that render
/// it.
///
/// A list cannot be a [MiracleValue]: `List` compares by identity, and these
/// lists are live views over native memory that hand back a fresh Dart object
/// per read — so every notify would look like a change and rebuild the whole
/// editor, wiping the text field somebody was typing a command into.
///
/// [signature] is therefore a string carrying exactly what the editor renders,
/// which is the same discipline every store in this shell notifies under. The
/// builder is handed the configuration rather than the signature, because what
/// it wants is the list.
class MiracleCollection extends StatelessWidget {
  const MiracleCollection({
    super.key,
    required this.store,
    required this.signature,
    required this.builder,
  });

  final MiracleConfigStore store;
  final String Function(MiracleConfig config) signature;
  final Widget Function(BuildContext context, MiracleConfig config) builder;

  @override
  Widget build(BuildContext context) => StoreSelector<String>(
    listenable: store,
    selector: () {
      final config = store.config;
      return config == null ? '' : signature(config);
    },
    builder: (context, _) {
      final config = store.config;
      if (config == null) return const SizedBox.shrink();
      return builder(context, config);
    },
  );
}

/// A fixed-width dropdown over an enum, labelled by [labelOf].
///
/// Every enum on these pages is offered in full, including the members whose
/// spelling in the configuration file is odd or whose meaning is niche: a
/// configuration may already name any of them, and an editor that hid one would
/// drop it silently on the next save.
Widget miracleEnumDropdown<T>({
  required List<T> values,
  required T selected,
  required String Function(T value) labelOf,
  required ValueChanged<T> onSelected,
  double width = kMiracleControlWidth,
  int searchFrom = 8,
}) => SizedBox(
  width: width,
  child: SettingsDropdown<T>(
    items: [
      for (final value in values)
        SettingsDropdownItem(value: value, label: labelOf(value)),
    ],
    selected: selected,
    onSelected: onSelected,
    searchFrom: searchFrom,
  ),
);

/// A right-aligned read-only value, for a row the configuration reports but
/// nothing can change.
class MiracleReadOnly extends StatelessWidget {
  const MiracleReadOnly(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
