import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'package:graceful_shell/dbus_clients.dart';

/// A held claim on the machine's power key.
///
/// Abstract because the interesting half is *when* the shell holds one (see
/// [PowerKeyService]), and that reconciliation has to be testable on a machine
/// with no logind — a unit test that took a real inhibitor would be a test
/// that changes what its host does when somebody presses the power button.
abstract class PowerInhibitor {
  /// Takes the lock, if it is not already held. Throws when the bus or logind
  /// refuses — the caller records that as a failed service rather than
  /// pretending the key is intercepted.
  Future<void> take();

  /// Gives the lock back. Safe to call when nothing is held.
  Future<void> release();

  /// Whether the lock is currently held.
  bool get isHeld;
}

/// systemd-logind's `handle-power-key` inhibitor, over the system bus.
///
/// This is the half of "intercept the power button" that has nothing to do
/// with Wayland. logind opens the ACPI power-button device *itself* — it does
/// not care what the compositor delivers to which client — and on a press it
/// runs `HandlePowerKey`, which is `poweroff` out of the box. So a shell that
/// only registered a global trigger would draw its power menu onto a machine
/// that was already going down.
///
/// `block` rather than `delay`: delay is for work that must happen *before*
/// the action (flushing a filesystem, saving a session) and logind proceeds
/// once the lock is released or `InhibitDelayMaxSec` expires. What is wanted
/// here is for logind never to act at all, which is what block means. It costs
/// nothing while held (a blocked key is exactly the key the shell answers)
/// and it is released the moment the fd closes, including when the shell
/// crashes, so it cannot leave a machine that will not power off.
///
/// Only `handle-power-key` is claimed. `handle-power-key-long-press` is
/// deliberately left alone: holding the button is the deliberate "get me out
/// of here" gesture and should keep doing whatever logind is configured to do,
/// and naming it here would fail outright on logind older than v250, which
/// answers an unknown inhibitor kind with `InvalidArgs`.
class LogindPowerInhibitor implements PowerInhibitor {
  LogindPowerInhibitor({DBusClient? bus, String why = _defaultWhy})
      : _bus = bus,
        _why = why;

  static const String _defaultWhy =
      'Graceful Shell shows the power menu on a power-key press';

  static const String _busName = 'org.freedesktop.login1';
  static const String _managerInterface = 'org.freedesktop.login1.Manager';

  /// Null means the process-wide [systemBus], resolved at [take] rather than
  /// in the constructor: this object is built while the shell's shortcut table
  /// is, which is also what a unit test builds, and nothing should open a
  /// connection to the system bus for a list of key bindings.
  final DBusClient? _bus;
  final String _why;

  /// The inhibitor fd, wrapped so it has an owner and a close. logind holds
  /// the lock for exactly as long as this stays open.
  RandomAccessFile? _lock;

  @override
  bool get isHeld => _lock != null;

  @override
  Future<void> take() async {
    if (isHeld) return;
    final object = DBusRemoteObject(
      _bus ?? systemBus,
      name: _busName,
      path: DBusObjectPath('/org/freedesktop/login1'),
    );
    final reply = await object.callMethod(
      _managerInterface,
      'Inhibit',
      [
        const DBusString('handle-power-key'),
        const DBusString('Graceful Shell'),
        DBusString(_why),
        const DBusString('block'),
      ],
      replySignature: DBusSignature('h'),
    );
    // Ownership of the descriptor transfers here: `toFile` is what gives it a
    // close, and closing it is the only way to give the key back.
    _lock = reply.returnValues.first.asUnixFd().toFile();
    debugPrint('power: holding logind handle-power-key inhibitor');
  }

  @override
  Future<void> release() async {
    final lock = _lock;
    if (lock == null) return;
    _lock = null;
    try {
      await lock.close();
      debugPrint('power: released logind handle-power-key inhibitor');
    } catch (e) {
      // The fd is gone either way (logind drops the lock when the peer that
      // holds it disconnects); losing the close is not worth a failed shell.
      debugPrint('power: failed to release the logind inhibitor: $e');
    }
  }
}
