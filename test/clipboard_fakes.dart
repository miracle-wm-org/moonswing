// A clipboard held in memory, for the clipboard history's tests.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:moonswing/clipboard/wl_clipboard.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart' show ClipboardResult;

/// A clipboard held in memory: [offer] is what `wl-paste` would see, [emit]
/// is `wl-paste --watch` reporting a change.
class FakeClipboard implements ClipboardBackend {
  Map<String, Uint8List> offered = {};
  StreamController<ClipboardChange>? _watch;
  int watches = 0;
  final written = <(String, Uint8List)>[];
  ClipboardResult writeResult = ClipboardResult.copied;

  bool get watching => _watch != null && !_watch!.isClosed;

  void offer(Map<String, Object> types) {
    offered = {
      for (final MapEntry(:key, :value) in types.entries)
        key: value is String
            ? Uint8List.fromList(utf8.encode(value))
            : value as Uint8List,
    };
  }

  void emit([ClipboardChange change = ClipboardChange.data]) =>
      _watch!.add(change);

  void fail(ClipboardWatchFailure failure) {
    _watch!.addError(failure);
    unawaited(_watch!.close());
  }

  @override
  Stream<ClipboardChange> watch() {
    watches++;
    final controller = StreamController<ClipboardChange>();
    controller.onCancel = () {
      if (identical(_watch, controller)) _watch = null;
    };
    _watch = controller;
    return controller.stream;
  }

  @override
  Future<List<String>?> listTypes() async =>
      offered.isEmpty ? null : offered.keys.toList();

  @override
  Future<Uint8List?> read(String mime, {required int maxBytes}) async {
    final bytes = offered[mime];
    if (bytes == null || bytes.length > maxBytes) return null;
    return bytes;
  }

  @override
  Future<ClipboardResult> write(String mime, Stream<List<int>> data) async {
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    written.add((mime, Uint8List.fromList(bytes)));
    return writeResult;
  }
}

/// Lets the store's async capture run to the end — real file writes
/// included, which a microtask turn does not wait for.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
