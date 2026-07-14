import 'package:graceful_shell/overlay/calendar/event.dart';

enum CalendarProviderKind { google, caldav, outlook }

/// The account a provider is signed in as, for display in the UI.
class CalendarAccount {
  const CalendarAccount({
    required this.id,
    required this.kind,
    required this.label,
    this.email,
  });

  final String id;
  final CalendarProviderKind kind;

  /// Human-readable provider name, e.g. 'Google Calendar'.
  final String label;

  final String? email;
}

/// The sign-in itself is broken: consent was denied, the grant was revoked, the
/// refresh token expired. Retrying will not help — the account must be
/// reconnected, so the store drops its tokens when it sees this.
class CalendarAuthException implements Exception {
  const CalendarAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A transient failure: offline, a 5xx, a rate limit. The tokens are still good,
/// so the store keeps them and whatever events it already has.
class CalendarFetchException implements Exception {
  const CalendarFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A source of calendar events.
///
/// Everything the UI touches goes through this interface, so adding CalDAV or
/// Outlook later means writing one more implementation and one more connect
/// pane — the month grid, the agenda, and the store stay as they are.
abstract class CalendarProvider {
  String get id;
  CalendarProviderKind get kind;

  /// Whether the credentials this provider needs are present in the config.
  bool get isConfigured;

  /// Whether the user has completed sign-in and usable tokens are held.
  bool get isConnected;

  CalendarAccount? get account;

  /// Loads persisted credentials. Must not hit the network — it runs at
  /// shell startup.
  Future<void> restore();

  /// Runs the interactive sign-in. [onUrl], where a provider needs a browser,
  /// receives the URL so the UI can offer it for copy-paste.
  Future<void> connect({void Function(Uri url)? onUrl});

  /// Signs out: revokes remotely where possible, and always clears locally.
  Future<void> disconnect();

  /// Events overlapping the half-open window [from, to).
  Future<List<CalendarEvent>> fetchEvents(DateTime from, DateTime to);
}
