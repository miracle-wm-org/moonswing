// The one loaded copy of miracle-wm's configuration, and the Save/Reset cycle
// the settings page drives it through.
//
// Unlike `ConfigStore` — the shell's own config, which writes a debounced copy
// of every keystroke straight back to disk — this store is explicitly
// transactional, and it has to be. `~/.config/miracle-wm/config.yaml` belongs to
// the compositor the shell is running *inside*: a half-typed value written the
// moment it is typed is a value the user's next `reload_config` would apply, and
// there is no undo for a compositor that will not start. So edits accumulate in
// native memory, [save] is a deliberate act, and [reset] throws the batch away.
//
// Two rules from `CLAUDE.md` shape the rest of it:
//
//  * **One loaded configuration for the machine, held by leases.** Every read
//    and write here is FFI into `libmiracle-wm-c` against a `malloc`ed tree, and
//    two settings surfaces holding two of them would be two trees that disagree.
//  * **A failure is a visible state, not a silence.** miracle-wm may not be
//    installed at all, the library may be too old, and the user's file may not
//    parse. All three are states this exposes and the page renders — an empty
//    form is indistinguishable from a machine with no window manager on it.
library;

import 'package:flutter/foundation.dart';

import 'package:miracle/miracle.dart';

/// How far the store got towards a configuration the page can edit.
enum MiracleConfigStatus {
  /// Nothing has been asked for yet — no lease is held.
  idle,

  /// `libmiracle-wm-c` could not be loaded, so there is nothing to edit.
  ///
  /// The ordinary reason is that miracle-wm is not installed; see
  /// [MiracleConfigStore.unavailableReason] for what the library actually said.
  unavailable,

  /// A configuration is loaded. It may still carry [MiracleConfigStore.errors].
  loaded,

  /// The library is present but refused to produce a configuration.
  failed,
}

/// What became of the last [MiracleConfigStore.save].
enum MiracleSaveOutcome {
  /// No save has been attempted since the configuration was loaded or reset.
  none,

  /// The file was written. The user still has to make miracle re-read it.
  saved,

  /// The file was not written; see [MiracleConfigStore.saveErrors].
  failed,
}

/// The live, editable copy of miracle's configuration.
///
/// Consumers [acquire] it, read [config] inside a builder, mutate through [edit]
/// and finally [save] or [reset]. Every mutation notifies, so a surface renders
/// what is in the tree rather than what it last typed.
class MiracleConfigStore extends ChangeNotifier {
  MiracleConfigStore._({
    bool Function()? isAvailable,
    MiracleConfig Function()? open,
    String Function()? path,
  }) : _isAvailable = isAvailable ?? (() => MiracleConfig.isAvailable),
       _open = open ?? MiracleConfig.loadDefault,
       _path = path ?? (() => MiracleConfig.defaultConfigPath);

  /// The process-wide store.
  static final MiracleConfigStore instance = MiracleConfigStore._();

  /// A store that never touches `libmiracle-wm-c`.
  ///
  /// Widget tests run on a machine with no compositor and no configuration
  /// library, and the states worth pinning there are the ones with no
  /// configuration in them: "miracle-wm is not installed" and "your file did not
  /// load". Both are reachable by handing in a probe and an opener.
  @visibleForTesting
  factory MiracleConfigStore.forTesting({
    bool Function()? isAvailable,
    MiracleConfig Function()? open,
    String Function()? path,
  }) => MiracleConfigStore._(
    isAvailable: isAvailable ?? (() => false),
    open: open,
    path: path,
  );

  final bool Function() _isAvailable;
  final MiracleConfig Function() _open;
  final String Function() _path;

  int _leases = 0;
  MiracleConfig? _config;
  MiracleConfigStatus _status = MiracleConfigStatus.idle;
  String _unavailableReason = '';
  List<MiracleConfigError> _errors = const <MiracleConfigError>[];
  List<MiracleConfigError> _saveErrors = const <MiracleConfigError>[];
  MiracleSaveOutcome _saveOutcome = MiracleSaveOutcome.none;
  bool _dirty = false;
  bool _noticeDismissed = false;
  int _structureRevision = 0;

  /// The loaded configuration, or null in every state but
  /// [MiracleConfigStatus.loaded].
  ///
  /// Read it inside a builder rather than caching it: [reset] frees the tree and
  /// loads another, and the old object answers every accessor with a
  /// [StateError] afterwards.
  MiracleConfig? get config => _config;

  MiracleConfigStatus get status => _status;

  /// What `libmiracle-wm-c` said when it could not be loaded — which library
  /// names were tried and where. Empty unless [status] is
  /// [MiracleConfigStatus.unavailable] or [MiracleConfigStatus.failed].
  String get unavailableReason => _unavailableReason;

  /// The file [config] was read from, and the file [save] writes back to.
  String get path => _config?.path ?? _pathOrEmpty();

  /// Anything miracle objected to in the user's file when it was loaded.
  ///
  /// Warnings and errors both. A file with errors in it still loads — miracle
  /// keeps what it understood — so this is rendered beside an editable form
  /// rather than instead of one.
  List<MiracleConfigError> get errors => _errors;

  /// Whether any of [errors] is serious.
  bool get hasErrors => _config?.hasErrors ?? false;

  /// Whether there are edits that [save] would write and [reset] would discard.
  bool get dirty => _dirty;

  MiracleSaveOutcome get saveOutcome => _saveOutcome;

  /// What went wrong in the last [save], or what it warned about.
  List<MiracleConfigError> get saveErrors => _saveErrors;

  /// Whether the "now reload miracle" notice should be showing.
  ///
  /// True from a successful [save] until the user dismisses it or edits again —
  /// the prompt is about the file that is on disk *now*, and it stops being
  /// about it as soon as the form moves away from it again.
  bool get showReloadNotice =>
      _saveOutcome == MiracleSaveOutcome.saved && !_noticeDismissed && !_dirty;

  /// Takes a lease, loading the configuration if this is the first.
  ///
  /// Never notifies: it runs inside the acquirer's `initState`, which is the
  /// rule every lease in this shell keeps. The acquirer's first build reads
  /// [status].
  void acquire() {
    _leases++;
    if (_leases > 1) return;
    // A configuration held across a release is one with unsaved edits in it
    // (see [release]); reloading here would discard them because the user
    // closed the settings overlay, which is not something they asked for.
    if (_config != null) return;
    _load();
  }

  /// Releases a lease, freeing the configuration when the last one goes.
  ///
  /// **Unless there are unsaved edits.** The tree is native memory and the whole
  /// point of a lease is not to hold it for an unbounded time — but the bound
  /// here is the user's own Save or Reset, and silently throwing away a form
  /// somebody had filled in because they glanced at another page would be worse
  /// than the megabyte.
  void release() {
    if (_leases == 0) return;
    _leases--;
    if (_leases > 0 || _dirty) return;
    _free();
    _status = MiracleConfigStatus.idle;
    _errors = const <MiracleConfigError>[];
    _saveErrors = const <MiracleConfigError>[];
    _saveOutcome = MiracleSaveOutcome.none;
    _noticeDismissed = false;
  }

  /// Runs [mutate] against the loaded configuration and tells everybody.
  ///
  /// The single write path, so that "something changed" cannot be forgotten at
  /// one of the seventy setters this page drives. A no-op when nothing is
  /// loaded, which is what a control left on screen through a [reset] failure
  /// would otherwise do.
  void edit(void Function(MiracleConfig config) mutate) {
    final config = _config;
    if (config == null) return;
    mutate(config);
    _dirty = true;
    // The save notice is about a file that matched the form. It no longer does.
    _noticeDismissed = false;
    notifyListeners();
  }

  /// [edit], for a change that adds, removes or reorders an element of one of
  /// the configuration's collections.
  ///
  /// The distinction exists for one reason, and it is a bug the settings UI has
  /// hit before: the editors for these lists put a `SettingsTextField` on each
  /// row, and a text field seeds its controller once and then ignores its
  /// widget's `initial`. Rows are matched to their state by *position*, so
  /// deleting the first of three bindings leaves the second row's field showing
  /// the text of the row that was above it.
  ///
  /// So a structural change bumps [structureRevision], and the editors key
  /// their rows on it — which discards every row's state and re-seeds each
  /// field from the configuration. Typing goes through [edit] and does not bump
  /// it, so a keystroke never costs the caret its place.
  void editStructure(void Function(MiracleConfig config) mutate) {
    _structureRevision++;
    edit(mutate);
  }

  /// Bumped by [editStructure]; part of the key an editable list row is built
  /// under.
  int get structureRevision => _structureRevision;

  /// Writes the configuration back to [path].
  ///
  /// Returns whether it was written. The errors either way are in [saveErrors];
  /// a *successful* save can still carry warnings, and those are worth showing.
  bool save() {
    final config = _config;
    if (config == null) return false;
    final result = config.save();
    _saveErrors = result.errors;
    _saveOutcome = result.success
        ? MiracleSaveOutcome.saved
        : MiracleSaveOutcome.failed;
    if (result.success) {
      _dirty = false;
      _noticeDismissed = false;
    }
    notifyListeners();
    return result.success;
  }

  /// Throws the edits away and re-reads the file.
  ///
  /// A fresh load rather than an undo log: `libmiracle-wm-c` has no way to roll
  /// a tree back, and the file on disk is the only other copy of what the user
  /// started from.
  void reset() {
    _free();
    _load();
    notifyListeners();
  }

  /// Hides the "now reload miracle" notice.
  void dismissReloadNotice() {
    if (!showReloadNotice) return;
    _noticeDismissed = true;
    notifyListeners();
  }

  /// Tries again after a [MiracleConfigStatus.failed] load.
  ///
  /// The recoverable case this exists for: the user installed miracle-wm, or
  /// fixed the YAML by hand, without restarting the shell — neither of which the
  /// shell can see happen.
  void retry() {
    _free();
    _load();
    notifyListeners();
  }

  String _pathOrEmpty() {
    try {
      return _path();
    } on MiracleConfigException {
      return '';
    }
  }

  /// Loads, recording *why* rather than throwing.
  ///
  /// A service throws and `ShellServices` records it; this is not one of those —
  /// it is a page the user opened, and every failure here has a sentence and a
  /// Retry attached to it.
  void _load() {
    _structureRevision++;
    if (!_isAvailable()) {
      _status = MiracleConfigStatus.unavailable;
      _unavailableReason = _probeReason();
      return;
    }
    try {
      _config = _open();
      _errors = _config!.errors;
      _status = MiracleConfigStatus.loaded;
      _unavailableReason = '';
    } on MiracleConfigException catch (error) {
      _status = MiracleConfigStatus.failed;
      _unavailableReason = error.message;
    }
    _dirty = false;
    _saveErrors = const <MiracleConfigError>[];
    _saveOutcome = MiracleSaveOutcome.none;
    _noticeDismissed = false;
  }

  /// The library's own explanation, which it only gives by throwing.
  ///
  /// [MiracleConfig.isAvailable] answers a bool; the sentence naming the
  /// sonames it tried and the directories it looked in comes out of the
  /// exception, and that sentence is the whole of what the page can tell a user
  /// whose miracle-wm is installed somewhere unusual.
  String _probeReason() {
    try {
      _path();
    } on MiracleConfigException catch (error) {
      return error.message;
    } catch (_) {
      // A probe that failed some other way is still an unavailable library;
      // falling through leaves the page its own default sentence.
    }
    return '';
  }

  void _free() {
    _config?.dispose();
    _config = null;
    _dirty = false;
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }
}
