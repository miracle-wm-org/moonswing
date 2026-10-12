// The Default Apps pane's model: what "Web browser" or "Images" stands for in
// content types, and the pure arithmetic over a choice.
//
// Widget-free, so the table and the claim rule are plain unit tests. The
// associations themselves are GIO's (`default_app_associations.dart`), which
// reads and writes the XDG `mimeapps.list` every other desktop reads too — the
// shell keeps no copy of its own.
library;

import 'package:flutter/foundation.dart' show immutable;

/// An application that can be made a default, as the pane shows it.
///
/// Plain values, never a `GAppInfo*`: a choice is looked up again by [id] when it
/// is applied, so nothing here owns a reference that a refresh could free out
/// from under an open dropdown.
@immutable
class HandlerApp {
  const HandlerApp({required this.id, required this.name, this.iconName = ''});

  /// The desktop-file id, `.desktop` suffix included — `firefox.desktop`. The
  /// spelling `mimeapps.list` stores, and what `g_desktop_app_info_new` takes.
  final String id;

  /// The localised display name.
  final String name;

  /// What `AppIconImage` draws: a themed name or an absolute path. Empty for an
  /// entry with no icon.
  final String iconName;

  @override
  bool operator ==(Object other) =>
      other is HandlerApp &&
      other.id == id &&
      other.name == name &&
      other.iconName == iconName;

  @override
  int get hashCode => Object.hash(id, name, iconName);

  @override
  String toString() => 'HandlerApp($id)';
}

/// One row of the pane's "Defaults" section — a kind of application, and the
/// content types choosing one claims.
@immutable
class DefaultAppCategory {
  const DefaultAppCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.primaryType,
    this.alsoTypes = const <String>[],
    this.family,
    this.tags = const <String>[],
  });

  /// Stable identity. The settings search addresses the row as
  /// `default_apps.<id>`.
  final String id;

  /// The row's label — also the search catalogue's, which is built from this
  /// table rather than spelled again beside it.
  final String label;

  /// One sentence for the search result's second line.
  final String description;

  /// The content type the row *reads*: whatever handles it is shown as the
  /// current choice, and only applications declaring it are offered.
  final String primaryType;

  /// Further types a choice claims, when the chosen application declares them.
  ///
  /// Never forced onto an application that does not: making a mail client the
  /// handler of `message/rfc822` because it was picked for `mailto:` links is
  /// right, while making a browser that never claimed `about:` the handler of
  /// it would send those links to something that cannot open them.
  final List<String> alsoTypes;

  /// A media-type prefix — `image/` — whose every member the chosen application
  /// declares is claimed too. GNOME's rule for its Photos, Music and Video
  /// rows: picking an image viewer should not leave WebP opening in whatever
  /// had it before.
  final String? family;

  /// Words somebody might type to find the row that are not in its label.
  final List<String> tags;

  /// Whether choosing for this row can change [type]'s default — what a reset
  /// has to undo, and what decides whether the row offers one.
  bool covers(String type) {
    if (type == primaryType || alsoTypes.contains(type)) return true;
    final family = this.family;
    return family != null && type.startsWith(family);
  }
}

/// The rows of the "Defaults" section, in the order the pane renders them.
///
/// The primary types are the ones `xdg-open` actually resolves for the thing in
/// the label: a link is `x-scheme-handler/https` rather than `text/html`, which
/// is a *file* and so belongs to the browser only by convention.
const List<DefaultAppCategory> kDefaultAppCategories = [
  DefaultAppCategory(
    id: 'browser',
    label: 'Web browser',
    description:
        'What opens web links — from a notification, a terminal, or any '
        'application calling xdg-open — and saved web pages.',
    primaryType: 'x-scheme-handler/https',
    alsoTypes: [
      'x-scheme-handler/http',
      'text/html',
      'application/xhtml+xml',
      'x-scheme-handler/about',
      'x-scheme-handler/unknown',
    ],
    tags: ['internet', 'web', 'firefox', 'chrome', 'chromium', 'links', 'url'],
  ),
  DefaultAppCategory(
    id: 'email',
    label: 'Email',
    description: 'What opens mailto: links and saved email messages.',
    primaryType: 'x-scheme-handler/mailto',
    alsoTypes: ['message/rfc822'],
    tags: ['mail', 'mailto', 'thunderbird', 'evolution', 'client'],
  ),
  DefaultAppCategory(
    id: 'calendar',
    label: 'Calendar',
    description: 'What opens calendar invitations and webcal: subscriptions.',
    primaryType: 'text/calendar',
    alsoTypes: ['x-scheme-handler/webcal'],
    tags: ['ics', 'invitation', 'event', 'webcal'],
  ),
  DefaultAppCategory(
    id: 'files',
    label: 'File manager',
    description:
        'What opens folders — from the desktop, a download notification or '
        'another application\'s "Show in folder".',
    primaryType: 'inode/directory',
    tags: ['folder', 'directory', 'nautilus', 'thunar', 'dolphin', 'nemo'],
  ),
  DefaultAppCategory(
    id: 'text',
    label: 'Text editor',
    description: 'What opens plain text files.',
    primaryType: 'text/plain',
    tags: ['editor', 'notepad', 'txt', 'gedit', 'kate'],
  ),
  DefaultAppCategory(
    id: 'images',
    label: 'Images',
    description:
        'What opens pictures. Choosing one claims every image format it '
        'supports.',
    primaryType: 'image/jpeg',
    family: 'image/',
    tags: ['photos', 'pictures', 'viewer', 'png', 'jpeg', 'jpg'],
  ),
  DefaultAppCategory(
    id: 'music',
    label: 'Music',
    description:
        'What plays audio files. Choosing one claims every audio format it '
        'supports.',
    primaryType: 'audio/mpeg',
    family: 'audio/',
    tags: ['audio', 'player', 'songs', 'mp3', 'flac', 'sound'],
  ),
  DefaultAppCategory(
    id: 'video',
    label: 'Video',
    description:
        'What plays video files. Choosing one claims every video format it '
        'supports.',
    primaryType: 'video/mp4',
    family: 'video/',
    tags: ['movies', 'player', 'mp4', 'mkv', 'vlc', 'mpv'],
  ),
  DefaultAppCategory(
    id: 'pdf',
    label: 'PDF documents',
    description: 'What opens PDF files.',
    primaryType: 'application/pdf',
    tags: ['pdf', 'reader', 'viewer', 'evince', 'okular', 'document'],
  ),
  DefaultAppCategory(
    id: 'documents',
    label: 'Word processor',
    description: 'What opens word-processor documents.',
    primaryType: 'application/vnd.oasis.opendocument.text',
    alsoTypes: [
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/msword',
      'application/rtf',
    ],
    tags: ['office', 'docx', 'odt', 'libreoffice', 'writer', 'word'],
  ),
  DefaultAppCategory(
    id: 'spreadsheets',
    label: 'Spreadsheets',
    description: 'What opens spreadsheets.',
    primaryType: 'application/vnd.oasis.opendocument.spreadsheet',
    alsoTypes: [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel',
      'text/csv',
    ],
    tags: ['office', 'xlsx', 'ods', 'csv', 'calc', 'excel'],
  ),
  DefaultAppCategory(
    id: 'archives',
    label: 'Archives',
    description: 'What opens zip files, tarballs and other archives.',
    primaryType: 'application/zip',
    alsoTypes: [
      'application/x-tar',
      'application/x-compressed-tar',
      'application/x-bzip-compressed-tar',
      'application/x-xz-compressed-tar',
      'application/x-zstd-compressed-tar',
      'application/gzip',
      'application/x-7z-compressed',
      'application/vnd.rar',
      'application/x-rar',
    ],
    tags: ['zip', 'tar', 'compressed', '7z', 'rar', 'extract', 'file roller'],
  ),
];

/// The content types choosing an application for [category] claims, given the
/// types that application declares ([declared]).
///
/// The primary type always, since the user picked the application for exactly
/// that; the rest only where declared — see [DefaultAppCategory.alsoTypes].
/// Ordered and duplicate-free, so the writes are deterministic.
List<String> typesToClaim(
  DefaultAppCategory category,
  Iterable<String> declared,
) {
  final supported = declared.toSet();
  final claimed = <String>[category.primaryType];
  for (final type in category.alsoTypes) {
    if (supported.contains(type) && !claimed.contains(type)) claimed.add(type);
  }
  final family = category.family;
  if (family != null) {
    final members = supported.where((t) => t.startsWith(family)).toList()
      ..sort();
    for (final type in members) {
      if (!claimed.contains(type)) claimed.add(type);
    }
  }
  return claimed;
}

/// The content types a `mimeapps.list` names a default for.
///
/// Read off the `[Default Applications]` group only: `[Added Associations]`
/// widens what is *offered* and `[Removed Associations]` narrows it, but neither
/// is a choice the pane can show a reset for. A key with an empty value names
/// nothing. Malformed lines cost that line — this is somebody's hand-edited
/// file.
Set<String> parseMimeAppsDefaults(String contents) {
  final defaults = <String>{};
  var inDefaults = false;
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      inDefaults = line == '[Default Applications]';
      continue;
    }
    if (!inDefaults) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (key.isEmpty || !key.contains('/')) continue;
    if (value.split(';').every((id) => id.trim().isEmpty)) continue;
    defaults.add(key);
  }
  return defaults;
}

/// The prefix a URL-scheme pseudo type carries.
const String kSchemeHandlerPrefix = 'x-scheme-handler/';

/// One content type in the "All file types" list.
@immutable
class ContentTypeInfo {
  const ContentTypeInfo({required this.type, required this.description});

  /// The MIME type, `image/png`.
  final String type;

  /// What to call it — see [describeContentType].
  final String description;

  @override
  bool operator ==(Object other) =>
      other is ContentTypeInfo &&
      other.type == type &&
      other.description == description;

  @override
  int get hashCode => Object.hash(type, description);
}

/// What to call [type] in the list, given what GIO calls it ([gioDescription],
/// shared-mime-info's comment).
///
/// A URL scheme has no comment of its own — GIO falls back to "x-scheme-handler/
/// mailto type", which reads as an error — so it is named after the links it
/// opens. Anything else with no description is shown as its type.
String describeContentType(String type, String gioDescription) {
  if (type.startsWith(kSchemeHandlerPrefix)) {
    final scheme = type.substring(kSchemeHandlerPrefix.length);
    if (scheme.isNotEmpty) return '$scheme: links';
  }
  final description = gioDescription.trim();
  return description.isEmpty ? type : description;
}

/// Sorts [types] the way the list shows them: by what they are called, then by
/// type, so two formats sharing a description still list stably.
List<ContentTypeInfo> sortContentTypes(Iterable<ContentTypeInfo> types) {
  final sorted = types.toList();
  sorted.sort((a, b) {
    final byName = a.description.toLowerCase().compareTo(
      b.description.toLowerCase(),
    );
    return byName != 0 ? byName : a.type.compareTo(b.type);
  });
  return sorted;
}

/// The types in [types] matching [query], in [types]' order.
///
/// Every word of the query has to appear in the description or the type —
/// "png image" and "image/png" both find PNG, and "mail" finds both the scheme
/// and the message format. An empty query matches everything.
List<ContentTypeInfo> filterContentTypes(
  List<ContentTypeInfo> types,
  String query,
) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return types;
  return [
    for (final info in types)
      if (_matchesAll(
        '${info.description.toLowerCase()} ${info.type.toLowerCase()}',
        words,
      ))
        info,
  ];
}

bool _matchesAll(String haystack, List<String> words) {
  for (final word in words) {
    if (!haystack.contains(word)) return false;
  }
  return true;
}

/// [apps] with [current] guaranteed among them, de-duplicated by id and sorted
/// by name.
///
/// The default can legitimately be something GIO would not *offer* for the
/// type — a `mimeapps.list` written by hand, or an application that has since
/// stopped declaring it — and a dropdown whose selection is not one of its rows
/// shows a dash where the answer should be.
List<HandlerApp> handlerOptions(
  Iterable<HandlerApp> apps,
  HandlerApp? current,
) {
  final byId = <String, HandlerApp>{};
  if (current != null) byId[current.id] = current;
  for (final app in apps) {
    byId.putIfAbsent(app.id, () => app);
  }
  final options = byId.values.toList();
  options.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return options;
}
