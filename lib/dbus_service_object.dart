import 'package:dbus/dbus.dart';

/// Declarative scaffolding for the shell's exported D-Bus objects.
///
/// Every server object the shell exports (the notification daemon, the
/// StatusNotifierWatcher, and the three ScreenCast portal objects) used to
/// hand-roll the same four overrides: an interface guard plus a method-name
/// switch in `handleMethodCall`, and one property table repeated in
/// `getProperty`, `getAllProperties`, and `introspect`. [DBusServiceObject]
/// derives all four from a single [DBusServiceInterface] declaration, so a
/// method or property is listed exactly once and the interface guard exists
/// by construction.
///
/// This file is deliberately Flutter-free (it imports `package:dbus` alone):
/// the screencast portal imports no Flutter so `tool/screencast_spike.dart`
/// can compile it standalone, and this file sits underneath it.

/// Handles one D-Bus method call on an interface the object serves.
///
/// Argument validation stays inside the handler, as it always has — a wrong
/// signature answers `DBusMethodErrorResponse.invalidArgs()` from there.
typedef DBusServiceMethodHandler = Future<DBusMethodResponse> Function(
    DBusMethodCall call);

/// Catch-all error policy for one interface: what a throwing handler answers
/// with instead of propagating (e.g. `invalidArgs`, or a portal error result).
typedef DBusServiceErrorHandler = DBusMethodResponse Function(
    DBusMethodCall call, Object error);

/// One method an object serves: its handler and its introspection arguments.
class DBusServiceMethod {
  const DBusServiceMethod(this.handler, {this.args = const []});

  final DBusServiceMethodHandler handler;

  /// Arguments reported by `Introspect` — descriptive only; nothing validates
  /// incoming calls against them.
  final List<DBusIntrospectArgument> args;
}

/// One read-only property: its D-Bus signature and how to read it.
///
/// Read-only is all the shell serves — none of its objects overrides
/// `setProperty`, so writes keep answering `unknownProperty` from the
/// [DBusObject] default, and introspection reports `access="read"`.
class DBusServiceProperty {
  DBusServiceProperty(this.signature, this.getter);

  final DBusSignature signature;
  final DBusValue Function() getter;
}

/// One interface an object serves: its methods, properties and signals,
/// declared once. Map literals iterate in declaration order, so introspection
/// output lists members in the order they are written here.
class DBusServiceInterface {
  DBusServiceInterface(
    this.name, {
    this.methods = const {},
    this.properties = const {},
    this.signals = const [],
    this.onError,
  });

  final String name;
  final Map<String, DBusServiceMethod> methods;
  final Map<String, DBusServiceProperty> properties;

  /// Introspection-only: emitting a signal is still an explicit `emitSignal`
  /// call from the owning object.
  final List<DBusIntrospectSignal> signals;

  /// When set, a handler that throws answers with this instead of letting the
  /// error propagate. When null, errors propagate as before.
  final DBusServiceErrorHandler? onError;
}

/// A [DBusObject] whose entire bus surface — dispatch, properties, and
/// introspection — is derived from [interfaces].
abstract class DBusServiceObject extends DBusObject {
  DBusServiceObject(super.path);

  /// The interfaces this object serves. Read on every incoming call, so
  /// property getters may close over live state; declare the table itself
  /// with `late final` when it never changes.
  List<DBusServiceInterface> get interfaces;

  DBusServiceInterface? _interfaceNamed(String? name) {
    for (final iface in interfaces) {
      if (iface.name == name) return iface;
    }
    return null;
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    final iface = _interfaceNamed(methodCall.interface);
    if (iface == null) return DBusMethodErrorResponse.unknownInterface();
    final method = iface.methods[methodCall.name];
    if (method == null) return DBusMethodErrorResponse.unknownMethod();
    final onError = iface.onError;
    if (onError == null) return method.handler(methodCall);
    try {
      return await method.handler(methodCall);
    } catch (e) {
      return onError(methodCall, e);
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final property = _interfaceNamed(interface)?.properties[name];
    if (property == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(property.getter());
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    final iface = _interfaceNamed(interface);
    return DBusGetAllPropertiesResponse({
      if (iface != null)
        for (final entry in iface.properties.entries)
          entry.key: entry.value.getter(),
    });
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
        for (final iface in interfaces)
          DBusIntrospectInterface(
            iface.name,
            methods: [
              for (final entry in iface.methods.entries)
                DBusIntrospectMethod(entry.key, args: entry.value.args),
            ],
            signals: iface.signals,
            properties: [
              for (final entry in iface.properties.entries)
                DBusIntrospectProperty(entry.key, entry.value.signature,
                    access: DBusPropertyAccess.read),
            ],
          ),
      ];
}
