// The OAuth client every Moonswing sign-in to Google runs as: the project's own
// "Desktop app" client, in the Google Cloud project `moonswing-509717`.
//
// Shipped in the source, the way `kGithubDefaultClientId` is, because an
// installed application cannot keep a secret — anything in the binary is one
// `strings` away — and Google's documentation for installed apps says as much:
// for this client type the secret is not treated as a secret. What protects a
// user is not the secret but the consent they give in their own browser, and
// PKCE plus a loopback port (`google_oauth.dart`), which make a stolen
// authorization code worthless.
//
// What the public pair does let a stranger do is build their own program that
// shows a "Moonswing" consent screen, or spend the app's user cap and API quota.
// The remedy for either is rotating the client: create a new Desktop client in
// the Cloud Console and replace these two constants. A grant saved under the old
// client is then dropped on load with a message asking the user to sign in
// again (`GoogleAccountStore`), rather than failing at the first refresh.
//
// The app is unverified, which caps it at 100 users over its lifetime and shows
// every user Google's "unverified app" warning on the consent page. How the
// project, its consent screen and this client were set up — and what it takes to
// lift the cap — is `docs/google-cloud-setup.md`.
//
// GitHub secret scanning recognises the `GOCSPX-` prefix; an alert on this file
// is expected and can be closed as a deliberately public client secret.

/// The project's Desktop OAuth client ID.
const String kGoogleClientId =
    '310646277602-156ps1mie8qi85jcopa3dtfifohk025h.apps.googleusercontent.com';

/// The secret Google issued beside [kGoogleClientId]. Public by design; see the
/// file comment.
const String kGoogleClientSecret = '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';
