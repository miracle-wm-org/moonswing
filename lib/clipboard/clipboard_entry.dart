// The clipboard history's pure half: what an entry is, which of the types a
// selection offers is the one worth remembering, and how an entry is described.
//
// Flutter-free, so every rule in it is a unit test.
library;

import 'dart:convert';

/// What an entry holds, which decides how it is drawn and how it is put back.
enum ClipboardKind {
  /// Text, kept in the index itself.
  text,

  /// Picture data — a screenshot, an image copied out of a browser. Kept as a
  /// file beside the index and drawn as a thumbnail.
  image,

  /// Files copied in a file manager: a `text/uri-list`, kept as text. Videos,
  /// documents and folders are all this — a file manager copies the *path*.
  files,

  /// Audio or video data put on the clipboard directly, kept as a file.
  media,

  /// Anything else with a real MIME type (a PDF, say), kept as a file.
  binary;

  /// Whether the payload lives in a file beside the index rather than in it.
  bool get storesFile => this == image || this == media || this == binary;
}

/// The type a selection advertises when its owner wants it kept out of
/// clipboard histories — KeePassXC, KDE's password managers. An offer carrying
/// it is never recorded, whatever else it offers.
const String kSecretClipboardHint = 'x-kde-passwordManagerHint';

/// The type a restored text entry is offered as. `wl-copy` adds the legacy
/// aliases (`UTF8_STRING`, `text/plain`, …) for a text type itself.
const String kClipboardTextMime = 'text/plain;charset=utf-8';

/// The plain-text spellings, best first. The charset-qualified one first, for
/// the reason `copyTextToClipboard` spells it: a bare `text/plain` may be read
/// as Latin-1 by the receiving end.
const List<String> _plainTextTypes = [
  'text/plain;charset=utf-8',
  'text/plain;charset=UTF-8',
  'UTF8_STRING',
  'text/plain',
  'STRING',
  'TEXT',
];

/// Image types Flutter can decode, best first.
const List<String> _imageTypes = [
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/webp',
  'image/gif',
  'image/bmp',
];

/// Which of a selection's types to read, and what that makes the entry.
typedef ClipboardChoice = ({ClipboardKind kind, String mime});

/// Picks the one type worth recording from everything a selection offers, or
/// null when nothing in it is (only private or X11 bookkeeping targets, or the
/// [kSecretClipboardHint]).
///
/// The order is the design:
///
/// 1. **Files** first. A file manager offers a path list and often plain text
///    of the same paths; the paths are what was copied.
/// 2. **Text over pictures, when both are offered.** An office suite offers a
///    rendering of a text selection as a bitmap; the text is what the user
///    selected. A browser's "Copy Image" offers no plain text at all, so a
///    picture still wins there — which is what makes this rule safe.
/// 3. Pictures, then audio/video data, then other text (`text/html` alone),
///    then any other real document type.
ClipboardChoice? pickClipboardType(Iterable<String> offered) {
  final types = [
    for (final raw in offered)
      if (raw.trim() case final type when type.isNotEmpty) type,
  ];
  if (types.contains(kSecretClipboardHint)) return null;
  final lower = {for (final t in types) t.toLowerCase(): t};

  if (lower.containsKey('text/uri-list')) {
    return (kind: ClipboardKind.files, mime: lower['text/uri-list']!);
  }
  if (lower.containsKey('x-special/gnome-copied-files')) {
    return (
      kind: ClipboardKind.files,
      mime: lower['x-special/gnome-copied-files']!,
    );
  }

  String? firstOf(List<String> wanted) {
    for (final w in wanted) {
      if (types.contains(w)) return w;
      if (lower[w.toLowerCase()] case final found?) return found;
    }
    return null;
  }

  final plain = firstOf(_plainTextTypes);
  if (plain != null) return (kind: ClipboardKind.text, mime: plain);

  final image =
      firstOf(_imageTypes) ??
      types.where((t) => t.toLowerCase().startsWith('image/')).firstOrNull;
  if (image != null) return (kind: ClipboardKind.image, mime: image);

  final media = types.where((t) {
    final l = t.toLowerCase();
    return l.startsWith('video/') || l.startsWith('audio/');
  }).firstOrNull;
  if (media != null) return (kind: ClipboardKind.media, mime: media);

  final otherText = types
      .where((t) => t.toLowerCase().startsWith('text/'))
      .firstOrNull;
  if (otherText != null) return (kind: ClipboardKind.text, mime: otherText);

  // A real document type, never an application's private one: `application/x-*`
  // and `application/vnd.*` are formats only their owner can paste, and an
  // entry that pastes into nothing is clutter.
  final document = types.where((t) {
    final l = t.toLowerCase();
    if (!l.startsWith('application/')) return false;
    final sub = l.substring('application/'.length);
    return !sub.startsWith('x-') && !sub.startsWith('vnd.');
  }).firstOrNull;
  if (document != null) return (kind: ClipboardKind.binary, mime: document);

  return null;
}

/// The local paths in a `text/uri-list` (or GNOME's `copy\nfile://…` variant),
/// in order. Empty when any line is not a `file:` URI — a list of web links is
/// text, not files, and is recorded as such.
List<String> parseFileUris(String raw) {
  final lines = const LineSplitter()
      .convert(raw)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  // `x-special/gnome-copied-files` leads with the operation.
  if (lines.isNotEmpty && (lines.first == 'copy' || lines.first == 'cut')) {
    lines.removeAt(0);
  }
  final paths = <String>[];
  for (final line in lines) {
    final uri = Uri.tryParse(line);
    if (uri == null || uri.scheme != 'file') return const [];
    try {
      paths.add(uri.toFilePath());
    } catch (_) {
      return const [];
    }
  }
  return paths;
}

/// The `text/uri-list` a set of [paths] is put back on the clipboard as. CRLF
/// line ends, as RFC 2483 spells the format.
String fileUriList(List<String> paths) =>
    paths.map((p) => '${Uri.file(p)}\r\n').join();

/// One remembered selection.
class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.kind,
    required this.mime,
    required this.copiedAt,
    required this.size,
    required this.hash,
    this.text,
    this.pinned = false,
  });

  /// Unique within the history, and the payload file's name for the kinds
  /// that have one.
  final String id;

  final ClipboardKind kind;

  /// The type the payload was read as, and is offered back as.
  final String mime;

  /// When it was last on the clipboard. Copying an entry again moves it to the
  /// top and moves this with it.
  final DateTime copiedAt;

  /// The payload's size in bytes.
  final int size;

  /// A digest of the kind and payload, which is how a selection already in the
  /// history is recognised rather than recorded twice.
  final String hash;

  /// The text for [ClipboardKind.text], the uri-list for
  /// [ClipboardKind.files]; null for the kinds kept in a file.
  final String? text;

  /// Pinned entries survive "Clear" and are never trimmed.
  final bool pinned;

  /// The local paths of a [ClipboardKind.files] entry.
  List<String> get paths =>
      kind == ClipboardKind.files ? parseFileUris(text ?? '') : const [];

  ClipboardEntry copyWith({DateTime? copiedAt, bool? pinned}) => ClipboardEntry(
    id: id,
    kind: kind,
    mime: mime,
    copiedAt: copiedAt ?? this.copiedAt,
    size: size,
    hash: hash,
    text: text,
    pinned: pinned ?? this.pinned,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'mime': mime,
    'copied_at': copiedAt.millisecondsSinceEpoch,
    'size': size,
    'hash': hash,
    if (text != null) 'text': text,
    if (pinned) 'pinned': true,
  };

  /// One row of the index, or null when the row will not parse — a bad row
  /// costs that entry, never the history.
  static ClipboardEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kindName = raw['kind'];
    final mime = raw['mime'];
    final at = raw['copied_at'];
    final size = raw['size'];
    final hash = raw['hash'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || id.contains('/') || id.contains('..')) {
      return null;
    }
    if (mime is! String || at is! int || size is! int || hash is! String) {
      return null;
    }
    final kind = ClipboardKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    if (!kind.storesFile && text is! String) return null;
    return ClipboardEntry(
      id: id,
      kind: kind,
      mime: mime,
      copiedAt: DateTime.fromMillisecondsSinceEpoch(at),
      size: size,
      hash: hash,
      text: text is String ? text : null,
      pinned: raw['pinned'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardEntry &&
          other.id == id &&
          other.kind == kind &&
          other.mime == mime &&
          other.copiedAt == copiedAt &&
          other.size == size &&
          other.hash == hash &&
          other.text == text &&
          other.pinned == pinned;

  @override
  int get hashCode =>
      Object.hash(id, kind, mime, copiedAt, size, hash, text, pinned);
}

/// What kind of file a path names, by extension — for the icon a copied file
/// is drawn with, and whether it can be drawn as a thumbnail.
enum ClipboardFileKind { image, video, audio, document, folder, other }

ClipboardFileKind fileKindForPath(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (path.endsWith('/')) return ClipboardFileKind.folder;
  if (dot <= slash) return ClipboardFileKind.other;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'webp' ||
    'gif' ||
    'bmp' => ClipboardFileKind.image,
    'mp4' ||
    'mkv' ||
    'webm' ||
    'mov' ||
    'avi' ||
    'm4v' ||
    'ogv' => ClipboardFileKind.video,
    'mp3' ||
    'flac' ||
    'ogg' ||
    'oga' ||
    'opus' ||
    'wav' ||
    'm4a' => ClipboardFileKind.audio,
    'pdf' ||
    'txt' ||
    'md' ||
    'odt' ||
    'doc' ||
    'docx' ||
    'ods' ||
    'xlsx' => ClipboardFileKind.document,
    _ => ClipboardFileKind.other,
  };
}

/// The last segment of [path], for a file row's label.
String fileBaseName(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final slash = p.lastIndexOf('/');
  return slash < 0 ? p : p.substring(slash + 1);
}

/// The subtype of [mime] in capitals — `image/png` is `PNG` — for a label.
String _subtypeLabel(String mime) {
  final slash = mime.indexOf('/');
  var sub = slash < 0 ? mime : mime.substring(slash + 1);
  final semi = sub.indexOf(';');
  if (semi >= 0) sub = sub.substring(0, semi);
  if (sub.startsWith('x-')) sub = sub.substring(2);
  final plus = sub.indexOf('+');
  if (plus >= 0) sub = sub.substring(0, plus);
  return sub.toUpperCase();
}

/// The few words an entry's card leads with: "Text", "PNG image", "3 files".
String describeClipboardEntry(ClipboardEntry entry) {
  switch (entry.kind) {
    case ClipboardKind.text:
      return 'Text';
    case ClipboardKind.image:
      return '${_subtypeLabel(entry.mime)} image';
    case ClipboardKind.files:
      final paths = entry.paths;
      if (paths.length == 1) {
        return switch (fileKindForPath(paths.single)) {
          ClipboardFileKind.image => 'Image file',
          ClipboardFileKind.video => 'Video file',
          ClipboardFileKind.audio => 'Audio file',
          ClipboardFileKind.folder => 'Folder',
          _ => 'File',
        };
      }
      return '${paths.length} files';
    case ClipboardKind.media:
      final video = entry.mime.toLowerCase().startsWith('video/');
      return '${_subtypeLabel(entry.mime)} ${video ? 'video' : 'audio'}';
    case ClipboardKind.binary:
      return _subtypeLabel(entry.mime);
  }
}

/// A byte count for a person: `512 B`, `14 KB`, `1.2 MB`.
String formatClipboardSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value < 10 ? value.toStringAsFixed(1) : value.round();
  return '$digits ${units[unit]}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// When an entry was copied, as a wall-clock time rather than an age.
///
/// Deliberately not "3 min ago": an age has to be redrawn as it goes stale,
/// which is a timer the panel would hold open all day. A time is true for as
/// long as it is on screen.
String formatCopiedAt(DateTime at, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  // Rounded, since a day across a DST change is 23 or 25 hours.
  final daysAgo = (today.difference(day).inMinutes / (24 * 60)).round();
  if (daysAgo <= 0) return clock;
  if (daysAgo == 1) return 'Yesterday $clock';
  if (daysAgo < 7) return '${_weekdays[at.weekday - 1]} $clock';
  final date = '${at.day} ${_months[at.month - 1]}';
  return at.year == now.year ? date : '$date ${at.year}';
}

/// A text entry's preview: the text with its outer blank lines dropped and
/// cut short, since the card shows at most a few lines of it.
String clipboardTextPreview(String text, {int maxChars = 400}) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars)}…';
}
