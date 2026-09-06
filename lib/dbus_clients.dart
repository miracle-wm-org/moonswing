import 'package:dbus/dbus.dart';

/// The process-wide D-Bus connections.
///
/// A `DBusClient` owns a socket; opening one per query — worse, one per poll tick
/// on a repeating timer, which is what the network module used to do — churns
/// connections forever. Share these instead, and never `close()` them.
///
/// The bluetooth page is the deliberate exception and keeps per-operation
/// clients: BlueZ scopes discovery to the requesting connection, so closing the
/// client is what *guarantees* discovery stops even when `StopDiscovery` fails.
final DBusClient systemBus = DBusClient.system();

/// See [systemBus]. The long-lived services (notifications, tray, MPRIS)
/// already hold their own session connections whose lifecycles they own;
/// this one is for one-shot queries.
final DBusClient sessionBus = DBusClient.session();
