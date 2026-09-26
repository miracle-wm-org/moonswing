// Registers nothing. An `AudioPlayer` constructed on Linux therefore has no
// platform behind it — which is fine, because nothing in the shell constructs
// one. See the `dependency_overrides:` entry in the root pubspec.yaml.

/// The Linux "implementation" of audioplayers: none.
class AudioplayersLinuxNone {
  /// Called by the generated Dart plugin registrant.
  static void registerWith() {}
}
