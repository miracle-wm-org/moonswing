import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:graceful_shell/overlay/file_picker.dart';

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
/// drawn underneath every application window and every panel. The root puts one
/// on the overlay layer instead.
///
/// Shaped like `ScreencastPickerController`, including its rule: a request with
/// nothing listening is declined immediately rather than left hanging, so a
/// headless run or a unit test never awaits a window that will not appear.
class FilePickerController extends ChangeNotifier {
  FilePickerController._();

  static final FilePickerController instance = FilePickerController._();

  @visibleForTesting
  factory FilePickerController.forTesting() => FilePickerController._();

  FilePickerRequest? _pending;
  Completer<List<String>?>? _completer;

  /// The request awaiting a window, or null.
  FilePickerRequest? get pending => _pending;

  /// Asks the shell to show a picker, resolving to the chosen absolute paths or
  /// null if it was cancelled.
  Future<List<String>?> pick(FilePickerRequest request) {
    if (!hasListeners) return Future<List<String>?>.value(null);

    // A second request supersedes the first, which is resolved as cancelled —
    // the same posture the screencast picker takes, and it means no caller is
    // ever left awaiting a window that has been replaced.
    _resolve(null);

    final completer = Completer<List<String>?>();
    _pending = request;
    _completer = completer;
    notifyListeners();
    return completer.future;
  }

  /// Called by the root once the user answers. Idempotent.
  void complete(List<String>? paths) {
    if (_pending == null && _completer == null) return;
    _resolve(paths);
    notifyListeners();
  }

  void _resolve(List<String>? paths) {
    final completer = _completer;
    _completer = null;
    _pending = null;
    if (completer != null && !completer.isCompleted) completer.complete(paths);
  }

  @override
  void dispose() {
    // A shell tearing down still owes every awaiting caller an answer.
    _resolve(null);
    super.dispose();
  }
}
