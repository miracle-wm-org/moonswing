import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:ubuntu_session/ubuntu_session.dart';

import 'package:graceful_shell/lock/lock_controller.dart';
import 'package:graceful_shell/power/power_config.dart';

/// One thing the shell can do to the session or the machine.
///
/// The verbs used to be spelled inline in the system module's popup, one closure
/// per button, which is why that menu had no Restart while the power menu did.
/// There is one power surface now — the power menu, which both the physical key
/// and the bar's power icon open — and it draws this list.
enum PowerAction {
  lock('Lock', FontAwesomeIcons.lock),
  logout('Log Out', FontAwesomeIcons.arrowRightFromBracket),
  suspend('Sleep', FontAwesomeIcons.moon),
  reboot('Restart', FontAwesomeIcons.arrowRotateRight),
  shutdown('Shut Down', FontAwesomeIcons.powerOff);

  const PowerAction(this.label, this.icon);

  /// What the tile says.
  final String label;

  /// The glyph the menu draws. Beside [label] for its reason: a verb's word and
  /// its picture belong to the verb, not to whatever surface is listing it.
  ///
  /// [FaIconData] rather than `IconData`: it is a *wrapper* around one rather
  /// than a subclass, and `FaIcon` — which draws these, because the plain `Icon`
  /// clips a non-square Font Awesome glyph — takes only the wrapper.
  final FaIconData icon;
}

/// The order the power menu lists them in: least destructive first, so the tile
/// that ends the uptime is the furthest from an accidental click.
const List<PowerAction> kPowerMenuActions = PowerAction.values;

/// The action a `[power] key_action` names, or null when it names none —
/// [PowerKeyAction.menu] asks for the dialog rather than a verb, and
/// [PowerKeyAction.none] for nothing at all.
PowerAction? powerActionFor(PowerKeyAction action) => switch (action) {
      PowerKeyAction.lock => PowerAction.lock,
      PowerKeyAction.logout => PowerAction.logout,
      PowerKeyAction.suspend => PowerAction.suspend,
      PowerKeyAction.reboot => PowerAction.reboot,
      PowerKeyAction.shutdown => PowerAction.shutdown,
      PowerKeyAction.menu || PowerKeyAction.none => null,
    };

/// Performs [action] on the real session.
typedef PowerActionRunner = Future<void> Function(PowerAction action);

/// The seam between "a button was pressed" and the machine actually going down.
///
/// A static rather than a constructor parameter because both call sites are
/// several layers from anything that could inject one, and because what a test
/// needs is not a *different* runner but *no* runner: a widget test that
/// suspends the machine running it is not one anybody runs twice.
abstract final class PowerActions {
  /// Replaced by tests, restored in their teardown.
  @visibleForTesting
  static PowerActionRunner runner = performPowerAction;

  static Future<void> run(PowerAction action) => runner(action);
}

/// The real implementation of [PowerActions.runner].
///
/// [UbuntuSession] resolves the session manager the desktop actually has (GNOME's,
/// MATE's, or systemd-logind as the fallback), which is why logout, reboot and
/// shutdown go through it. Suspend has no place in that interface, so it goes to
/// logind directly.
Future<void> performPowerAction(PowerAction action) async {
  switch (action) {
    case PowerAction.lock:
      LockController.instance.lock();
    case PowerAction.logout:
      await UbuntuSession().logout();
    case PowerAction.reboot:
      await UbuntuSession().reboot();
    case PowerAction.shutdown:
      await UbuntuSession().shutdown();
    case PowerAction.suspend:
      final manager = SystemdSessionManager();
      await manager.connect();
      await manager.suspend(false);
      await manager.close();
  }
}
