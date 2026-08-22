/// The file-extension predicates that decide how a media path renders.
///
/// Pure and I/O-free on purpose: existence is checked separately at call
/// sites, so these stay unit-testable predicates. Shared by the background
/// rotation, the lock screen wallpaper, the file picker's filters, and the
/// settings UI's wallpaper list.
library;

/// File extensions considered valid image wallpapers. Paths with any other
/// extension (or none) are treated as invalid and auto-pruned by the selector.
const Set<String> imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
};

/// File extensions rendered with the video backend rather than as a still.
const Set<String> videoExtensions = {
  '.mp4',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.m4v',
};

/// Whether [path] points at a supported image file, judged purely by its
/// extension. Existence is checked separately at call sites so this stays a
/// pure, unit-testable predicate.
bool isImagePath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return false;
  return imageExtensions.contains(lower.substring(dot));
}

/// Whether [path] is rendered with the video backend, judged purely by its
/// extension like [isImagePath].
bool isVideoPath(String path) {
  final lower = path.toLowerCase();
  return videoExtensions.any(lower.endsWith);
}
