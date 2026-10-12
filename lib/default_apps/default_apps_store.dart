// The Default Apps pane's state: what opens each kind of file now, what could,
// and the user's changes to it.
//
// Nothing here polls. The associations change when the user changes them here —
// every write re-reads what it wrote — or when something else edits
// `mimeapps.list`, which GIO's `GAppInfoMonitor` reports through `AppIndex`. The
// store only listens while the pane holds a lease on it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:moonswing/default_apps/default_app_associations.dart';
import 'package:moonswing/default_apps/default_app_model.dart';
import 'package:moonswing/launcher/app_index.dart';

/// One row's state: what opens its type now, and what the dropdown offers.
@immutable
class DefaultAppChoice {
  const DefaultAppChoice({
    required this.current,
    required this.options,
    required this.userSet,
  });

  /// What opens it now, or null when nothing does.
  final HandlerApp? current;

  /// Every application the row offers, [current] among them, sorted by name.
  final List<HandlerApp> options;

  /// Whether the user's own `mimeapps.list` decides it — the row has something
  /// for a reset to undo.
  final bool userSet;

  @override
  bool operator ==(Object other) =>
      other is DefaultAppChoice &&
      other.current == current &&
      other.userSet == userSet &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(current, userSet, Object.hashAll(options));
}

enum DefaultAppsStatus { loading, ready, failed }

/// The singleton behind Settings › Default Apps.
///
/// Leased the way every shared store is: the pane `acquire`s it in `initState`
/// and `release`s it in `dispose`, and the change listener exists only between
/// the two.
class DefaultAppsStore extends ChangeNotifier {
  DefaultAppsStore({
    DefaultAppAssociations associations = const GioDefaultAppAssociations(),
    Listenable? changes,
    List<DefaultAppCategory> categories = kDefaultAppCategories,
  }) : _associations = associations,
       _changes = changes,
       categories = List.unmodifiable(categories);

  static final DefaultAppsStore instance = DefaultAppsStore(
    changes: AppIndex.instance,
  );

  final DefaultAppAssociations _associations;

  /// Notifies when GIO's view of installed applications or their associations
  /// may have moved. `AppIndex` in the shell; nothing in a test.
  final Listenable? _changes;

  /// The "Defaults" rows, in order.
  final List<DefaultAppCategory> categories;

  int _leases = 0;
  bool _disposed = false;

  DefaultAppsStatus _status = DefaultAppsStatus.loading;
  DefaultAppsStatus get status => _status;

  Map<String, DefaultAppChoice> _categoryChoices = const {};
  Set<String> _userDefaults = const {};

  /// Per-type rows of the full list, read on first sight and dropped on any
  /// change — see [typeChoice].
  final Map<String, DefaultAppChoice> _typeChoices = {};

  List<ContentTypeInfo>? _types;

  /// Every type some application declares, sorted for display — or null until
  /// [showAllTypes] asks for them. Enumerating every application is the one
  /// read here that costs real time, and most visits never need it.
  List<ContentTypeInfo>? get types => _types;

  String _errorTitle = '';
  String _error = '';

  /// What went wrong, for the banner; empty when nothing did.
  String get errorTitle => _errorTitle;
  String get error => _error;

  /// Where choices are written, for the pane's prose. Empty until read.
  String _userListPath = '';
  String get userListPath => _userListPath;

  // -------------------------------------------------------------------------
  // Lease
  // -------------------------------------------------------------------------

  void acquire() {
    if (_leases++ > 0) return;
    _changes?.addListener(_onSystemChanged);
    // Never synchronously: this runs inside the acquirer's `initState`, and a
    // notify from there would mark a widget dirty mid-build.
    scheduleMicrotask(() {
      if (_leases > 0 && !_disposed) _refresh();
    });
  }

  void release() {
    if (_leases == 0) return;
    if (--_leases > 0) return;
    _changes?.removeListener(_onSystemChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_leases > 0) _changes?.removeListener(_onSystemChanged);
    super.dispose();
  }

  void _onSystemChanged() {
    if (_leases > 0 && !_disposed) _refresh();
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  /// [category]'s row, or null before the first read lands.
  DefaultAppChoice? categoryChoice(DefaultAppCategory category) =>
      _categoryChoices[category.id];

  /// [type]'s row in the full list.
  ///
  /// Read on first request rather than for every type up front: a desktop
  /// declares several hundred types, each answer constructs an appinfo per
  /// handler, and the list is lazy — only the rows on screen ever ask. Caching a
  /// read is not a change, so this never notifies; an unreadable type shows as
  /// having no handler rather than taking the list down.
  DefaultAppChoice typeChoice(String type) =>
      _typeChoices.putIfAbsent(type, () {
        try {
          final current = _associations.defaultFor(type);
          return DefaultAppChoice(
            current: current,
            options: handlerOptions(_associations.allFor(type), current),
            userSet: _userDefaults.contains(type),
          );
        } catch (error) {
          debugPrint('default-apps: could not read $type: $error');
          return const DefaultAppChoice(
            current: null,
            options: [],
            userSet: false,
          );
        }
      });

  /// Whether a [category] row has anything of the user's to reset.
  bool _categoryUserSet(DefaultAppCategory category) =>
      _userDefaults.any(category.covers);

  /// Reads the full list's types. Synchronous, and a no-op once read.
  void showAllTypes() {
    if (_types != null) return;
    try {
      _types = _readTypes();
    } catch (error) {
      _fail('Could not list file types', '$error');
    }
    notifyListeners();
  }

  List<ContentTypeInfo> _readTypes() {
    final types = {..._associations.handledTypes(), ..._userDefaults};
    return sortContentTypes([
      for (final type in types)
        ContentTypeInfo(
          type: type,
          description: describeContentType(type, _describe(type)),
        ),
    ]);
  }

  String _describe(String type) {
    try {
      return _associations.describe(type);
    } catch (_) {
      return '';
    }
  }

  /// Re-reads everything. What the banner's retry does.
  void retry() {
    _errorTitle = '';
    _error = '';
    _refresh(force: true);
  }

  /// Dismisses the banner after a failed write without re-reading.
  void clearError() {
    if (_error.isEmpty && _errorTitle.isEmpty) return;
    _errorTitle = '';
    _error = '';
    notifyListeners();
  }

  void _refresh({bool force = false}) {
    final previousStatus = _status;
    final previousCategories = _categoryChoices;
    final previousTypes = _types;
    final previousUserDefaults = _userDefaults;
    try {
      _userListPath = _associations.userListPath;
      _userDefaults = _associations.userDefaults();
      _categoryChoices = {
        for (final category in categories) category.id: _readCategory(category),
      };
      _typeChoices.clear();
      if (_types != null) _types = _readTypes();
      // A refresh that worked supersedes a failed *read*; a failed write's
      // banner stays until the user acts on it.
      if (_status == DefaultAppsStatus.failed) {
        _errorTitle = '';
        _error = '';
      }
      _status = DefaultAppsStatus.ready;
    } catch (error) {
      _status = DefaultAppsStatus.failed;
      _errorTitle = 'Default applications unavailable';
      _error = 'GIO could not be asked which applications open what: $error';
    }
    // `AppIndex` notifies for every installed or removed application, and every
    // surface of the pane listens, so a re-read that found the same answers
    // stays quiet.
    final changed =
        force ||
        _status != previousStatus ||
        !mapEquals(_categoryChoices, previousCategories) ||
        !listEquals(_types, previousTypes) ||
        !setEquals(_userDefaults, previousUserDefaults);
    // The one exception is an open full list. Its rows were dropped from the
    // cache above and only re-read when they build, so whether one of *them*
    // moved is unknowable without re-reading every row ever scrolled past — and
    // what this costs is a rebuild of the dozen on screen, on a change to the
    // installed applications, while the list is open.
    if (changed || _types != null) notifyListeners();
  }

  DefaultAppChoice _readCategory(DefaultAppCategory category) {
    final current = _associations.defaultFor(category.primaryType);
    return DefaultAppChoice(
      current: current,
      options: handlerOptions(
        _associations.recommendedFor(category.primaryType),
        current,
      ),
      userSet: _categoryUserSet(category),
    );
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Makes [app] the default for [category]: its primary type, and every
  /// further type the category claims that [app] declares. True on success; a
  /// failure is the banner.
  bool setCategoryDefault(DefaultAppCategory category, HandlerApp app) {
    return _write(app, () {
      final declared = _associations.declaredTypes(app.id);
      final claimed = typesToClaim(category, declared);
      for (final type in claimed) {
        _associations.setDefault(app.id, type);
      }
      return category.primaryType;
    });
  }

  /// Makes [app] the default for [type] alone.
  bool setTypeDefault(String type, HandlerApp app) {
    return _write(app, () {
      _associations.setDefault(app.id, type);
      return type;
    });
  }

  /// Hands every type [category] covers back to the system's defaults.
  void resetCategory(DefaultAppCategory category) {
    _reset([
      for (final type in _userDefaults)
        if (category.covers(type)) type,
    ]);
  }

  /// Hands [type] back to the system's default.
  void resetType(String type) => _reset([type]);

  void _reset(List<String> types) {
    try {
      for (final type in types) {
        _associations.reset(type);
      }
      _errorTitle = '';
      _error = '';
    } catch (error) {
      _fail('Could not reset the default application', '$error');
    }
    _refresh(force: true);
  }

  /// Runs [apply], which returns the type to check the write against, then
  /// re-reads — and says so when what was written is not what now applies.
  bool _write(HandlerApp app, String Function() apply) {
    var ok = false;
    try {
      final checked = apply();
      final now = _associations.defaultFor(checked);
      if (now?.id == app.id) {
        _errorTitle = '';
        _error = '';
        ok = true;
      } else {
        _fail('${app.name} was saved but is not in effect', _notInEffect(now));
      }
    } on DefaultAppException catch (error) {
      _fail('Could not change the default application', error.message);
    } catch (error) {
      _fail('Could not change the default application', '$error');
    }
    _refresh(force: true);
    return ok;
  }

  /// Why a choice GIO accepted still is not the answer GIO gives.
  ///
  /// GIO writes only the generic `mimeapps.list`, and the specification ranks a
  /// desktop's own `$desktop-mimeapps.list` in the same directory above it — so
  /// a choice made once through such a desktop's own settings goes on winning.
  /// The pane names that file rather than editing it: it is another program's,
  /// and somebody may keep it on purpose.
  String _notInEffect(HandlerApp? now) {
    final opens = now == null ? 'nothing' : now.name;
    List<String> lists;
    try {
      lists = _associations.overridingLists();
    } catch (_) {
      lists = const [];
    }
    if (lists.isNotEmpty) {
      return 'It is still opened by $opens, because ${lists.join(' and ')} '
          'takes precedence over $_userListPath and names something else. '
          'Remove that entry from it to let this choice apply.';
    }
    return 'It is still opened by $opens: a list with a higher precedence than '
        '$_userListPath names something else.';
  }

  void _fail(String title, String message) {
    _errorTitle = title;
    _error = message;
  }
}
