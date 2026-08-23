import 'package:flutter/foundation.dart';

import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/request_controller.dart';

/// What to show in a root-owned file picker window.
@immutable
class FilePickerRequest {
  const FilePickerRequest({
    required this.filters,
    this.allowMultiple = true,
    this.allowDirectories = false,
    this.initialDirectory,
  });

  final List<FilePickerFilter> filters;
  final bool allowMultiple;
  final bool allowDirectories;
  final String? initialDirectory;
}

/// The seam between "a surface that cannot host a modal wants a file picker"
/// and `_GracefulShellRootState`, which owns the windows.
///
/// [showFilePicker] inserts into the nearest root [Overlay], which is fine
/// inside the settings overlay but useless on the desktop: the background
/// surface is on the *background* layer, so a picker rendered there would be
/// drawn underneath every application window and every panel. The root puts
/// one on the overlay layer instead.
///
/// [pick] resolves to the chosen absolute paths, or null when cancelled —
/// the decline/supersede/teardown rules are [RequestController]'s.
class FilePickerController
    extends RequestController<FilePickerRequest, List<String>> {
  FilePickerController._();

  static final FilePickerController instance = FilePickerController._();

  @visibleForTesting
  factory FilePickerController.forTesting() => FilePickerController._();
}
