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

  static final _ModuleConfigNotifier _configChanges = _ModuleConfigNotifier();

  /// Fires once per [loadAll] in which some module's options actually moved.
  ///
  /// Module options are pushed *imperatively* — [loadAll] mutates each module's
  /// config in place and [builder] closes over it — so nothing about a module
  /// widget's inputs tells Flutter they changed. This is what says so; without it,
  /// toggling a `[modules.*]` option in the settings UI would silently do nothing
  /// until the next restart.
  ///
  /// Panels listen per module, so a `[modules.clock]` edit rebuilds the clock and
  /// nothing else.
  static Listenable get configChanges => _configChanges;

  /// Calls [loadConfig] on every registered module using [modulesMap], and
  /// fires [configChanges] if any of them took a new value.
  static void loadAll(Map<String, dynamic>? modulesMap) {
    var changed = false;
    for (final module in _registry.values) {
      // Type-tested, not cast: a `[modules.<key>]` that is not a table must
      // cost that module its options, not throw out of AppConfig.fromMap and
      // cost the user the whole config.
      final sub = modulesMap?[module.configKey];
      if (module.loadConfig(sub is Map<String, dynamic> ? sub : null)) {
        changed = true;
      }
    }
    // Once for the whole sweep, not once per module: `AppConfig.fromMap` calls
    // this, and `ConfigStore` notifies on every keystroke anywhere in the
    // settings UI.
    if (changed) _configChanges.fire();
  }

  /// Builds the standard module: a config parsed by [fromMap], handed to
  /// [builder]'s widget.
  ///
  /// Fourteen `Module` subclasses were this exact class modulo three identifiers;
  /// a new module is one call to this plus `Module.register` in `main()`.
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

  /// Loads the configuration for the given module, from the data at [configKey].
  ///
  /// Returns whether the options actually moved. [loadAll] runs on every
  /// `ConfigStore` notify — every keystroke anywhere in the settings UI — and only
  /// a true answer wakes [configChanges].
  bool loadConfig(Map<String, dynamic>? map);
}

/// [Module.configChanges] behind a `fire()` the registry can call;
/// `notifyListeners` is `@protected`.
class _ModuleConfigNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _SimpleModule<C> extends Module {
  _SimpleModule(this.configKey, this._fromMap, this._builder);

  @override
  final String configKey;

  final C Function(Map<String, dynamic>? map) _fromMap;
  final Widget Function(BuildContext context, C config) _builder;

  late C _config = _fromMap(null);

  /// The raw `[modules.<key>]` table [_config] was last built from, stringified —
  /// the `ConfigStore._restartSignature` idiom, for its reason: these `fromMap`s
  /// return a dozen unrelated types with no value equality between them, but the
  /// table they came from is always comparable. A false positive costs one
  /// rebuild; a false negative is impossible for the scalars and string lists
  /// these tables hold.
  ///
  /// Null until the first [loadConfig], so that one always counts as a change.
  String? _signature;

  @override
  bool loadConfig(Map<String, dynamic>? map) {
    final signature = '$map';
    if (_signature == signature) return false;
    _signature = signature;
    // Deliberately behind the guard: the system monitor's `fromMap` pushes
    // into `SystemStatsStore` as a side effect, and re-running that on every
    // keystroke is exactly what this is here to stop.
    _config = _fromMap(map);
    return true;
  }

  @override
  WidgetBuilder get builder => (context) => _builder(context, _config);
}
