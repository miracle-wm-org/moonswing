import 'package:flutter/widgets.dart';

/// A module that exists in a bar.
///
/// Modules should be places in the "module" folder and extend this class.
abstract class Module {
  static final Map<String, Module> _registry = {};

  /// Registers a module in the global registry.
  ///
  /// Must be called before [AppConfig.load] so that config is applied.
  static void register(Module m) => _registry[m.configKey] = m;

  /// Looks up a registered module by its [configKey].
  static Module? lookup(String key) => _registry[key];

  /// All registered module keys, in registration order. Used by the settings
  /// UI to offer the set of modules a panel slot can contain.
  static Iterable<String> get registeredKeys => _registry.keys;

  /// Calls [loadConfig] on every registered module using [modulesMap].
  static void loadAll(Map<String, dynamic>? modulesMap) {
    for (final module in _registry.values) {
      // Type-tested, not cast: a `[modules.<key>]` that is not a table must
      // cost that module its options, not throw out of AppConfig.fromMap and
      // cost the user the whole config.
      final sub = modulesMap?[module.configKey];
      module.loadConfig(sub is Map<String, dynamic> ? sub : null);
    }
  }

  /// Builds the standard module: a config parsed by [fromMap], handed to
  /// [builder]'s widget.
  ///
  /// Fourteen `Module` subclasses were this exact class modulo three
  /// identifiers; a new module is one call to this (plus `Module.register`
  /// in `main()`), not a subclass.
  static Module simple<C>({
    required String configKey,
    required C Function(Map<String, dynamic>? map) fromMap,
    required Widget Function(BuildContext context, C config) builder,
  }) =>
      _SimpleModule<C>(configKey, fromMap, builder);

  /// A module with no options of its own: its `[modules.<key>]` table is
  /// ignored.
  static Module plain({
    required String configKey,
    required WidgetBuilder builder,
  }) =>
      _SimpleModule<Null>(configKey, (_) => null, (context, _) => builder(context));

  /// The widget builder for this module.
  WidgetBuilder get builder;

  /// The configuration key for this module.
  ///
  /// This must be unique so-as not to interfere with other
  /// modules.
  String get configKey;

  /// Loads the configuration for the given module.
  ///
  /// The [map] will be the data provided at [configKey].
  void loadConfig(Map<String, dynamic>? map);
}

class _SimpleModule<C> extends Module {
  _SimpleModule(this.configKey, this._fromMap, this._builder);

  @override
  final String configKey;

  final C Function(Map<String, dynamic>? map) _fromMap;
  final Widget Function(BuildContext context, C config) _builder;

  late C _config = _fromMap(null);

  @override
  void loadConfig(Map<String, dynamic>? map) => _config = _fromMap(map);

  @override
  WidgetBuilder get builder => (context) => _builder(context, _config);
}
