// A `mimeapps.list` in memory, standing in for GIO in the Default Apps tests.

import 'package:moonswing/default_apps/default_app_associations.dart';
import 'package:moonswing/default_apps/default_app_model.dart';

const firefox = HandlerApp(id: 'firefox.desktop', name: 'Firefox');
const chromium = HandlerApp(id: 'chromium.desktop', name: 'Chromium');
const textEditor = HandlerApp(id: 'text-editor.desktop', name: 'Text Editor');
const loupe = HandlerApp(id: 'loupe.desktop', name: 'Image Viewer');
const gimp = HandlerApp(id: 'gimp.desktop', name: 'GIMP');

/// GIO's answers, computed from [declared] (each application's `MimeType=`),
/// [systemDefaults] (the system's choice) and [user] (the user's own list),
/// the way the specification layers them.
class FakeAssociations implements DefaultAppAssociations {
  FakeAssociations({
    Map<HandlerApp, List<String>>? declared,
    Map<String, String>? systemDefaults,
  }) : declared =
           declared ??
           {
             firefox: [
               'x-scheme-handler/https',
               'x-scheme-handler/http',
               'text/html',
             ],
             chromium: ['x-scheme-handler/https', 'x-scheme-handler/http'],
             textEditor: ['text/plain', 'text/markdown'],
             loupe: ['image/jpeg', 'image/png', 'image/webp'],
             gimp: ['image/jpeg', 'image/png', 'image/x-xcf'],
           },
       systemDefaults =
           systemDefaults ??
           {
             'x-scheme-handler/https': 'chromium.desktop',
             'x-scheme-handler/http': 'chromium.desktop',
             'text/plain': 'text-editor.desktop',
             'image/jpeg': 'gimp.desktop',
           };

  final Map<HandlerApp, List<String>> declared;
  final Map<String, String> systemDefaults;

  /// The user's `[Default Applications]`.
  final Map<String, String> user = {};

  /// Every `setDefault` call, in order, as `type=id`.
  final List<String> writes = [];

  /// Throws from every read while set — GIO missing a symbol.
  Object? failReads;

  /// Thrown from the next `setDefault`.
  DefaultAppException? failWrite;

  /// Types a desktop-specific list pins, so a write to them does not take.
  final Map<String, String> pinned = {};

  int defaultReads = 0;

  HandlerApp? _app(String? id) {
    if (id == null) return null;
    for (final app in declared.keys) {
      if (app.id == id) return app;
    }
    return null;
  }

  void _maybeFail() {
    final failure = failReads;
    if (failure != null) throw failure;
  }

  @override
  HandlerApp? defaultFor(String type) {
    _maybeFail();
    defaultReads++;
    return _app(pinned[type] ?? user[type] ?? systemDefaults[type]);
  }

  @override
  List<HandlerApp> recommendedFor(String type) {
    _maybeFail();
    return [
      for (final MapEntry(key: app, value: types) in declared.entries)
        if (types.contains(type)) app,
    ];
  }

  @override
  List<HandlerApp> allFor(String type) => recommendedFor(type);

  @override
  List<String> declaredTypes(String appId) {
    _maybeFail();
    return declared[_app(appId)] ?? const [];
  }

  @override
  Set<String> handledTypes() {
    _maybeFail();
    return {for (final types in declared.values) ...types};
  }

  @override
  void setDefault(String appId, String type) {
    _maybeFail();
    final failure = failWrite;
    if (failure != null) {
      failWrite = null;
      throw failure;
    }
    writes.add('$type=$appId');
    user[type] = appId;
  }

  @override
  void reset(String type) {
    _maybeFail();
    user.remove(type);
  }

  @override
  String describe(String type) => switch (type) {
    'image/png' => 'PNG image',
    'image/jpeg' => 'JPEG image',
    'text/plain' => 'plain text document',
    _ => '',
  };

  @override
  Set<String> userDefaults() {
    _maybeFail();
    return user.keys.toSet();
  }

  @override
  String get userListPath => '/home/me/.config/mimeapps.list';

  @override
  List<String> overridingLists() => [
    if (pinned.isNotEmpty) '/home/me/.config/miracle-wm-mimeapps.list',
  ];
}
