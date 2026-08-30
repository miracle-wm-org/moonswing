// systemd-localed, which is where the keyboard layout actually lives.
//
// This reaches the running compositor for free: miracle-wm constructs its
// keymap as `miral::Keymap::system_locale1()`, whose implementation subscribes
// to this object's `PropertiesChanged` and re-applies the keymap to every live
// keyboard device on the spot. So a `SetX11Keyboard` here changes the layout
// with no restart, no `libxkbcommon` binding, and no compositor IPC — miracle's
// own `input type:keyboard xkb_layout` command validates its payload and then
// discards it.
//
// Flutter-free, so the whole error mapping is a plain unit test.

import 'package:dbus/dbus.dart';

import 'package:graceful_shell/dbus_clients.dart';

const String kLocale1BusName = 'org.freedesktop.locale1';
const String kLocale1Path = '/org/freedesktop/locale1';

/// The X11 keyboard configuration, as locale1 reports it.
///
/// [layout] and [variant] are comma-separated *lists* when more than one group
/// is configured; see `activeSourceIndex` for which component the shell reads.
class Locale1Keyboard {
  const Locale1Keyboard({
    this.layout = '',
    this.model = '',
    this.variant = '',
    this.options = '',
  });

  final String layout;
  final String model;
  final String variant;
  final String options;

  Locale1Keyboard copyWith({
    String? layout,
    String? model,
    String? variant,
    String? options,
  }) => Locale1Keyboard(
    layout: layout ?? this.layout,
    model: model ?? this.model,
    variant: variant ?? this.variant,
    options: options ?? this.options,
  );

  @override
  bool operator ==(Object other) =>
      other is Locale1Keyboard &&
      other.layout == layout &&
      other.model == model &&
      other.variant == variant &&
      other.options == options;

  @override
  int get hashCode => Object.hash(layout, model, variant, options);

  @override
  String toString() =>
      'Locale1Keyboard(layout: $layout, model: $model, '
      'variant: $variant, options: $options)';
}

/// Why a write did not land.
///
/// [denied] and "no polkit authentication agent answered" are the **same**
/// answer at the wire — polkit returns `AccessDenied` for both — so nothing
/// below can tell them apart and [Locale1Failure.message] has to cover both.
enum Locale1FailureKind { denied, interactionRequired, unavailable, failed }

class Locale1Failure implements Exception {
  const Locale1Failure(this.kind, this.message);

  final Locale1FailureKind kind;

  /// A sentence for the user, not a D-Bus error name.
  final String message;

  @override
  String toString() => 'Locale1Failure($kind): $message';
}

/// Classifies a D-Bus error name into something the UI can word.
///
/// Pure, so `test/locale1_error_test.dart` pins the whole table.
Locale1Failure mapLocale1Error(String errorName, String detail) {
  switch (errorName) {
    case 'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired':
      return const Locale1Failure(
        Locale1FailureKind.interactionRequired,
        'This session could not ask for authorization to change the '
            'keyboard layout.',
      );
    case 'org.freedesktop.DBus.Error.AccessDenied':
    case 'org.freedesktop.DBus.Error.AuthFailed':
    case 'org.freedesktop.DBus.Error.NotSupported':
      return const Locale1Failure(
        Locale1FailureKind.denied,
        'The system refused the change. Setting the keyboard layout needs '
            'administrator approval, and this session could not obtain it.',
      );
    case 'org.freedesktop.DBus.Error.ServiceUnknown':
    case 'org.freedesktop.DBus.Error.NameHasNoOwner':
    case 'org.freedesktop.DBus.Error.NoReply':
    case 'org.freedesktop.DBus.Error.Timeout':
    case 'org.freedesktop.DBus.Error.TimedOut':
    case 'org.freedesktop.DBus.Error.NoServer':
    case 'org.freedesktop.DBus.Error.Disconnected':
      return const Locale1Failure(
        Locale1FailureKind.unavailable,
        "systemd's org.freedesktop.locale1 did not answer.",
      );
    default:
      return Locale1Failure(
        Locale1FailureKind.failed,
        detail.isEmpty ? 'The change could not be applied.' : detail,
      );
  }
}

/// The seam a test replaces. See [DBusLocale1Client] for the real one.
abstract class Locale1Client {
  Future<Locale1Keyboard> read();

  /// Fires whenever locale1 reports its keyboard properties moved — including
  /// when something outside the shell (`localectl`, another settings app) is
  /// what moved them.
  Stream<Locale1Keyboard> get changes;

  /// Writes all four components. Throws [Locale1Failure].
  Future<void> setKeyboard(Locale1Keyboard next, {bool convert});
}

class DBusLocale1Client implements Locale1Client {
  DBusLocale1Client({DBusClient? bus}) : _bus = bus;

  /// Null resolves to the process-wide [systemBus] at first use, so
  /// constructing one of these — which the store does eagerly — opens nothing.
  final DBusClient? _bus;

  DBusRemoteObject? _object;

  DBusRemoteObject get _remote =>
      _object ??= DBusRemoteObject(
        _bus ?? systemBus,
        name: kLocale1BusName,
        path: DBusObjectPath(kLocale1Path),
      );

  @override
  Future<Locale1Keyboard> read() async {
    try {
      final props = await _remote.getAllProperties(kLocale1BusName);
      String str(String key) {
        final value = props[key];
        return value is DBusString ? value.value : '';
      }

      return Locale1Keyboard(
        layout: str('X11Layout'),
        model: str('X11Model'),
        variant: str('X11Variant'),
        options: str('X11Options'),
      );
    } on DBusMethodResponseException catch (e) {
      throw mapLocale1Error(e.errorName, e.toString());
    } catch (e) {
      throw mapLocale1Error('', e.toString());
    }
  }

  /// Re-reads rather than trusting the signal payload.
  ///
  /// locale1 declares these properties `emits-change`, so the payload is
  /// complete today — but a property set that ever moved to `invalidates` would
  /// silently freeze the shell's view of the layout, and one `GetAll` per
  /// signal is free at this cadence.
  @override
  Stream<Locale1Keyboard> get changes => _remote.propertiesChanged
      .where((signal) => signal.propertiesInterface == kLocale1BusName)
      .asyncMap((_) => read())
      // A read that fails mid-stream is one missed update, not a dead
      // subscription: the store keeps what it had and the next signal corrects
      // it.
      .handleError((Object _) {});

  @override
  Future<void> setKeyboard(Locale1Keyboard next, {bool convert = true}) async {
    try {
      await _remote.callMethod(
        kLocale1BusName,
        'SetX11Keyboard',
        [
          DBusString(next.layout),
          DBusString(next.model),
          DBusString(next.variant),
          DBusString(next.options),
          DBusBoolean(convert),
          // True, and deliberately: false makes polkit answer
          // `InteractiveAuthorizationRequired` immediately even where an agent
          // exists, which is the wrong answer on every machine without
          // Ubuntu's gnome-control-center polkit rule. A prompt sitting up is
          // the user's to answer, so the call is simply awaited.
          const DBusBoolean(true),
        ],
        replySignature: DBusSignature(''),
      );
    } on DBusMethodResponseException catch (e) {
      throw mapLocale1Error(e.errorName, e.toString());
    } on Locale1Failure {
      rethrow;
    } catch (e) {
      throw mapLocale1Error('', e.toString());
    }
  }
}
