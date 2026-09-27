// The accounts linked under Settings › Accounts, and the content read through
// them, as one ambient scope — so a bar module or a desktop widget that wants
// the user's GitHub inbox or Google calendar asks its context for the store the
// rest of the shell is already using, rather than reaching for a singleton or
// running a sign-in of its own.
//
//   final github = AccountsScope.githubOf(context);   // GithubAccountStore
//   github.withToken((token) => ...);
//   final calendar = AccountsScope.googleCalendarOf(context);
//   final lease = calendar.acquire(from, to);
//
// The scope hands out *stores*, not snapshots: each is a `ChangeNotifier` with
// its own leases, and a consumer listens to the one it reads (a
// `ListenableBuilder`, or `StoreSelector` for one value). So the lookup does
// not register a dependency — the stores are fixed for the life of a window,
// and the scope rebuilding must not rebuild every consumer — and it is safe
// from `initState`, which is where a lease is taken.
//
// Every root-owned window gets one (`_windowChrome` in `main.dart`). A popup
// lays out under a FlutterView of its own with nothing above it, so every
// lookup falls back to the process-wide instance rather than throwing: a
// popup's content sees the same account its opener does. Tests put a scope of
// their own above the widget they pump, with stores over fakes, which is the
// point of injecting through a scope at all.

import 'package:flutter/widgets.dart';

import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_calendar_store.dart';

/// The shell's linked accounts and the content stores built on them.
class AccountsScope extends InheritedWidget {
  const AccountsScope({
    super.key,
    this.google,
    this.googleCalendar,
    this.github,
    this.githubNotifications,
    required super.child,
  });

  /// The process-wide stores — what `_windowChrome` provides.
  AccountsScope.shell({super.key, required super.child})
    : google = GoogleAccountStore.instance,
      googleCalendar = GoogleCalendarStore.instance,
      github = GithubAccountStore.instance,
      githubNotifications = GithubStore.instance;

  /// The Google accounts — any number — and the access token behind each.
  /// Null falls through to [GoogleAccountStore.instance].
  final GoogleAccountStore? google;

  /// Every selected calendar of every Google account, leased by time window.
  final GoogleCalendarStore? googleCalendar;

  /// The GitHub account and the token behind every request.
  final GithubAccountStore? github;

  /// The GitHub notification inbox, polled under a lease.
  final GithubStore? githubNotifications;

  static AccountsScope? _scope(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountsScope>();

  /// The Google accounts: [GoogleAccountStore.accounts], the sign-in, and
  /// [GoogleAccountStore.withAccessToken] for a request of a module's own.
  static GoogleAccountStore googleOf(BuildContext context) =>
      _scope(context)?.google ?? GoogleAccountStore.instance;

  /// The events of the calendars chosen under Settings › Accounts.
  static GoogleCalendarStore googleCalendarOf(BuildContext context) =>
      _scope(context)?.googleCalendar ?? GoogleCalendarStore.instance;

  /// The GitHub account: [GithubAccountStore.login], the sign-in, and
  /// [GithubAccountStore.withToken] for a request of a module's own.
  static GithubAccountStore githubOf(BuildContext context) =>
      _scope(context)?.github ?? GithubAccountStore.instance;

  /// The GitHub notification inbox.
  static GithubStore githubNotificationsOf(BuildContext context) =>
      _scope(context)?.githubNotifications ?? GithubStore.instance;

  @override
  bool updateShouldNotify(AccountsScope old) =>
      google != old.google ||
      googleCalendar != old.googleCalendar ||
      github != old.github ||
      githubNotifications != old.githubNotifications;
}
