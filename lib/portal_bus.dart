// The shell's xdg-desktop-portal backend bus name, shared by every portal
// interface the shell implements.
//
// A `.portal` file names one D-Bus name and lists the interfaces behind it, and
// the frontend talks to all of them at one path, `/org/freedesktop/portal/desktop`.
// So ScreenCast and InputCapture cannot each own a connection: one connection
// owns the name, and one object at that path serves the union of their
// interfaces. Each backend contributes its interfaces with [PortalBus.serve] and
// takes them back with [PortalBus.withdraw]; the last withdrawal gives the name
// up.
//
// Either backend can be switched off in `config.toml` and either can fail on its
// own (no PipeWire, no libeis) — which is why this is a lease on the name rather
// than something one of them owns.
//
// Flutter-free: `tool/screencast_spike.dart` runs both backends.

import 'dart:async';

import 'package:dbus/dbus.dart';

import 'dbus_service_object.dart';

const String kPortalBusName = 'org.freedesktop.impl.portal.desktop.moonswing';
const String kPortalObjectPath = '/org/freedesktop/portal/desktop';

class PortalBus {
  PortalBus._(this.client, this._desktop);

  static Future<PortalBus?>? _acquiring;

  /// The shared bus, claiming the name on the first call. Null is the graceful
  /// decline: another backend already owns [kPortalBusName]. Every caller sees
  /// the same answer until the last holder lets go.
  ///
  /// A non-null answer is a hold the caller must give back — with [withdraw]
  /// once it has served something, or [release] if it failed before it could.
  static Future<PortalBus?> acquire() async {
    final bus = await (_acquiring ??= _claim());
    bus?._holders++;
    return bus;
  }

  static Future<PortalBus?> _claim() async {
    final client = DBusClient.session();
    try {
      final reply = await client.requestName(kPortalBusName,
          flags: {DBusRequestNameFlag.doNotQueue});
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        await client.close();
        return null;
      }
      final desktop = _PortalDesktop();
      await client.registerObject(desktop);
      return PortalBus._(client, desktop);
    } catch (_) {
      _acquiring = null;
      unawaited(client.close());
      rethrow;
    }
  }

  /// The connection that owns the name. Backends register their per-session
  /// and per-request objects on it, and emit their signals through it.
  final DBusClient client;
  final _PortalDesktop _desktop;

  /// Adds [part]'s interfaces to the shared object. [part] itself is never
  /// registered — only its interface table is read — so it must emit signals
  /// with [emitSignal], not with its own `emitSignal`.
  void serve(DBusServiceObject part) {
    if (!_desktop.parts.contains(part)) _desktop.parts.add(part);
  }

  /// Takes [part]'s interfaces back and gives up the caller's hold.
  Future<void> withdraw(DBusServiceObject part) {
    _desktop.parts.remove(part);
    return release();
  }

  /// Gives up one hold from [acquire]. The last one out releases the name.
  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders > 0) return;
    _acquiring = null;
    await client.close();
  }

  int _holders = 0;

  /// A signal from the shared object, on [interface].
  Future<void> emitSignal(
          String interface, String name, List<DBusValue> values) =>
      client.emitSignal(
        path: DBusObjectPath(kPortalObjectPath),
        interface: interface,
        name: name,
        values: values,
      );
}

/// The object at [kPortalObjectPath]: every served part's interfaces, in the
/// order they were served.
class _PortalDesktop extends DBusServiceObject {
  _PortalDesktop() : super(DBusObjectPath(kPortalObjectPath));

  final List<DBusServiceObject> parts = [];

  @override
  List<DBusServiceInterface> get interfaces =>
      [for (final part in parts) ...part.interfaces];
}
