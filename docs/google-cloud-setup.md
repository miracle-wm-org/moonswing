# Moonswing's Google Cloud app

The Google sign-in under Settings › Accounts runs as one OAuth client that belongs to the
project. Its ID and secret are the two constants in `lib/google/google_client.dart`. This
page covers how that app was set up, how to keep it running, and what it takes to grow
past 100 users.

| | |
|---|---|
| Cloud project | `moonswing-509717` |
| Client type | Desktop app |
| Scope | `https://www.googleapis.com/auth/calendar.readonly` (sensitive) |
| Publishing status | In production, unverified: 100-user lifetime cap |
| Homepage | https://miracle-wm-org.github.io/moonswing/ |
| Privacy policy | https://miracle-wm-org.github.io/moonswing/privacy/ |
| Terms of service | https://miracle-wm-org.github.io/moonswing/terms/ |

## Why the secret is in the repository

An installed application cannot keep a secret, because anything in the binary can be read
out of it. Google's documentation for installed apps says the same: for this client type
the secret is not treated as a secret. Users are protected by the consent they give in their
own browser, and by PKCE plus a loopback redirect (`lib/google/google_oauth.dart`), which
make an intercepted authorization code worthless.

Anyone can therefore reuse the pair, either to show a "Moonswing" consent screen from
their own program or to spend the app's user cap and quota. If that happens, rotate the
client (below).

GitHub secret scanning recognises the `GOCSPX-` prefix. Close an alert on
`google_client.dart` as a deliberately public client secret. Push protection may also ask
you to allow the secret when it is first pushed.

## Setting it up from scratch

The Cloud Console moves things around. These steps match the Google Auth Platform layout
as of September 2026.

1. **Create the project.** At <https://console.cloud.google.com/>, open the project picker
   and choose **New project**, named *Moonswing*. Make it under an account or organisation
   the project controls, and turn on 2-step verification for that account.
2. **Enable the API.** Go to **APIs & Services › Library**, search for *Google Calendar API*
   and choose **Enable**.
3. **Start the consent screen.** Go to **Google Auth Platform › Get started** and enter:
   - App name: *Moonswing*
   - User support email: an address users may write to
   - Audience: **External**
   - Contact information: the developer address(es) Google writes to about the app

   Then accept the user data policy.
4. **Branding.** **Publish app** stays greyed out until this page has an app name, a
   support email, a homepage URL and a privacy policy URL.
   - Application home page: `https://miracle-wm-org.github.io/moonswing/`
   - Privacy policy: `https://miracle-wm-org.github.io/moonswing/privacy/`
   - Terms of service: `https://miracle-wm-org.github.io/moonswing/terms/`
   - Authorised domains: `miracle-wm-org.github.io`. `github.io` is a public suffix, so the
     organisation's subdomain is the domain.
   - **Leave the logo empty.** Uploading one puts the app through a brand review before the
     logo is shown.

   The pages must already be deployed: they are `website/src/content/docs/privacy.md` and
   `terms.md`, published by `.github/workflows/website.yml` from `main`. The homepage links
   to both, which Google checks.
5. **Data access.** Go to **Add or remove scopes**, add
   `https://www.googleapis.com/auth/calendar.readonly` and save. Add nothing else: the
   shell reads the signed-in address off the primary calendar's id, so it needs no
   `userinfo` scope. Each extra scope is something more to justify at verification.
6. **Create the client.** Go to **Clients › Create client**, choose **Desktop app** and
   name it *Moonswing desktop*. **Download the JSON straight away**, because Google now
   shows the secret only once. The downloaded `redirect_uris: ["http://localhost"]` is
   expected: Desktop clients accept `http://127.0.0.1:<any port>` without registering it,
   which is what the shell uses.
7. **Publish.** Go to **Audience › Publish app** and confirm, which moves it to
   **In production**.
   - Don't leave the app in *Testing*. There, every user must be added by hand as a test
     user, and their sign-ins expire after seven days.
   - In production but unverified, anyone can sign in after Google's "unverified app"
     warning (**Advanced › Go to Moonswing**), and sign-ins do not expire. Because the
     scope is sensitive, the app is capped at **100 users over its lifetime**. The
     Audience page shows how much of the cap is used.
8. **Ship it.** Put the ID and secret into `lib/google/google_client.dart`. The next
   nightly snap carries them.

## Keeping it healthy

- **Owners.** Add a second project owner under **IAM & Admin › IAM**, so that losing one
  account doesn't lose the app.
- **Quota.** Check **APIs & Services › Google Calendar API › Quotas**. Each shell polls
  only while something shows events (every `refresh_minutes`, default 5), and the default
  quota is far above what 100 users need.
- **Rotating the client.** Create a new Desktop client (step 6), replace both constants,
  then delete the old client once the build carrying the new one has shipped. A grant made
  under the old client can't be refreshed with the new one. `GoogleAccountStore` sees the
  saved `client_id` differ, revokes the old grant, and asks the user to sign in again.
  Nobody is left with a sign-in that silently fails.
- **Google's emails.** Policy notices go to the developer contact from step 3. An
  unanswered notice can end with the client suspended.

## Growing past 100 users: verification

Submit from **Google Auth Platform › Verification centre**. For a sensitive scope such as
`calendar.readonly` (sensitive, not restricted, so there is no security assessment),
Google asks for:

- **Proof that you own the domain** of the homepage and privacy policy, verified in
  [Google Search Console](https://search.google.com/search-console) by the same account
  that owns the Cloud project. For `miracle-wm-org.github.io`, use the *URL prefix*
  property `https://miracle-wm-org.github.io/moonswing/` and verify with an HTML file or a
  `<meta name="google-site-verification">` tag. The meta tag can go in the `head:` list in
  `website/astro.config.mjs`. Moving the site to a custom domain first also works, and
  looks more trustworthy on the consent screen.
- **The privacy policy**, which must describe the Google data used and include the Limited
  Use statement. `privacy.md` already does both. Keep it accurate if the shell starts using
  Google data differently.
- **A justification for the scope**: for example, "Read-only access to show the user's own
  calendar events in the desktop shell's calendar and put today's meetings on its local
  todo board. No data leaves the user's machine."
- **A demo video** (unlisted YouTube). It should show the consent screen with the app name
  and scope, the address bar showing the client ID, and the calendar data in use: the
  Calendar tab's events, and meeting cards on the todo board.

Verification usually takes a few days to a few weeks. Once it's approved, the cap and the
"unverified app" warning go away. The warning text in
`lib/overlay/settings/accounts.dart` and in `CONFIG.md` › Google Account can then be
removed.
