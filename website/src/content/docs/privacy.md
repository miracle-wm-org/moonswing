---
title: Privacy policy
description: What Moonswing does with your data, and in particular with a Google account you connect to it.
editUrl: false
lastUpdated: 2026-09-25
---

_Effective 25 September 2026._

Moonswing is a desktop shell that runs on your own computer. The project that makes it
runs **no server**. It collects no analytics or telemetry and has no account system of its
own. Everything described here happens on your machine, between your machine and the
services you choose to connect.

## Connecting a Google account

Connecting a Google account is optional. It is done under Settings › Accounts, through
Moonswing's Google app.

### What is accessed

Moonswing asks Google for one permission:
`https://www.googleapis.com/auth/calendar.readonly`, which is read-only access to your
calendars. With it the shell reads:

- **the list of your calendars** (their names and ids), so you can pick which ones to show.
  The id of your primary calendar is your email address, and the shell shows it on the
  Accounts page as the account you are signed in as;
- **the events on the calendars you select**, for the days being shown. Google returns each
  event's details, and the shell uses its title, time, location, meeting link and a link
  to the event's page.

Moonswing cannot create, change or delete anything in your Google account. It does not
read your email, contacts, files or any other Google data.

### How it is used

Calendar data is used only to show it back to you, in two places:

- the **Calendar tab**, which marks days that have events and lists a day's events with a
  **Join** button for meeting links;
- if you turn on **Put today's meetings on the todo board**, a card on your todo board for
  each of today's timed events.

### Where it goes and what is stored

Requests go directly from your computer to Google's APIs over HTTPS. Nothing is sent to the
Moonswing project or to anyone else.

On your computer:

- **Your sign-in** is a refresh token, kept in
  `~/.local/state/moonswing/google-account.json`. Only your user account can read that file
  (mode 0600).
- **Events** are held in memory while something is showing them, and are not written to
  disk.
- **Meeting cards** you chose to put on the todo board are saved with the rest of your
  board in `~/.local/share/moonswing/notes.db`. If you configured a backup server for the
  board, they go wherever you pointed it.

### Sharing

Moonswing does not sell, share or transfer your Google user data to anyone. It does not use
it for advertising, and does not use it to develop, improve or train AI or machine-learning
models.

Moonswing's use and transfer to any other app of information received from Google APIs will
adhere to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

### Disconnecting and deleting

- **Sign out** in Settings › Accounts revokes Moonswing's access at Google and deletes the
  saved sign-in from your computer.
- You can also revoke access at any time from
  [your Google account's third-party connections](https://myaccount.google.com/connections).
- To delete everything the shell has kept, remove
  `~/.local/state/moonswing/google-account.json`, and delete any meeting cards from the
  todo board (or remove `~/.local/share/moonswing/notes.db` to delete the whole board).

## Other network features

Some parts of the shell fetch data only when you turn them on. For example, the weather
module queries a weather service, and the GitHub module reads the account linked under
Settings › Accounts. They also talk
to those services directly from your computer, and nothing passes through the project.

## Changes

If this policy changes, the new version will be published on this page with a new
effective date. The history of every change is public in the
[project's repository](https://github.com/miracle-wm-org/moonswing).

## Contact

Questions about this policy or your data can be asked on the
[project's issue tracker](https://github.com/miracle-wm-org/moonswing/issues).
