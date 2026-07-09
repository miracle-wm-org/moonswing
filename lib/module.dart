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
      module.loadConfig(modulesMap?[module.configKey] as Map<String, dynamic>?);
    }
  }

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
