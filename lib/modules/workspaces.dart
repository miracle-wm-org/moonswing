import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/modules/workspace_apps.dart';
import 'package:graceful_shell/modules/workspace_menu.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_coordinator.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_services.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:miracle/miracle.dart';

export 'package:graceful_shell/modules/workspace_apps.dart'
    show WorkspacesConfig;

class Workspaces extends StatefulWidget {
  const Workspaces({super.key, required this.config});

  final WorkspacesConfig config;

  @override
  WorkspacesState createState() => WorkspacesState();
}

class WorkspacesState extends State<Workspaces> {
  List<WorkspaceResult> _workspaces = <WorkspaceResult>[];

  /// Every output miracle knows about, for the right-click menu's second page.
  ///
  /// Held rather than fetched when a menu opens, so the menu answers "where
  /// could this go" out of memory instead of on a round-trip — and re-read on
  /// miracle's own `output` event, never on a timer, which is the same rule the
  /// workspace list itself follows. It costs one `GET_OUTPUTS` per bar per
  /// hotplug, alongside the `GET_WORKSPACES` that event already triggers.
  List<OutputResult> _outputs = <OutputResult>[];

  MiracleManager? _manager;
  MiracleConnection? _connection;
  StreamSubscription<Event>? _events;

  /// Coalescing guards for the row's two round-trips, and the spelling of what
  /// each last put on screen.
  ///
  /// The row re-reads on every workspace and output event, and those arrive in
  /// bursts: focus-follows-mouse across the seam between two monitors is a
  /// workspace focus change per crossing, on every bar at once. Without the
  /// in-flight guard that is one `GET_WORKSPACES` per event per bar, all in
  /// flight together and landing in whatever order the socket answers them —
  /// so a stale reply could overwrite a newer one. Without the signature it is
  /// a `setState` per reply, and a bar has no repaint boundary of its own, so
  /// each of those re-records the whole panel picture and damages the whole
  /// output.
  bool _workspacesInFlight = false;
  bool _workspacesQueued = false;
  bool _outputsInFlight = false;
  bool _outputsQueued = false;
  String _workspacesSignature = '';
  String _outputsSignature = '';

  /// What is open on each workspace. Shared with every other bar on the
  /// machine, and only read while somebody's icons are switched on.
  final WorkspaceAppsStore _apps = WorkspaceAppsStore.instance;

  /// Whether this row is one of the holders of [_apps]'s lease.
  bool _leased = false;

  @override
  void initState() {
    super.initState();
    _apps.addListener(_onAppsChanged);
    _syncLease();
  }

  @override
  void didUpdateWidget(Workspaces oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `[modules.workspaces]` moved — the module's config is pushed
    // imperatively, so this is the only notice of it (see
    // [Module.configChanges]).
    _syncLease();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = MiracleScope.of(context);
    if (manager != _manager) {
      _manager?.removeListener(_onManagerChanged);
      _manager = manager..addListener(_onManagerChanged);
    }
    _syncConnection();
  }

  @override
  void dispose() {
    _manager?.removeListener(_onManagerChanged);
    _apps.removeListener(_onAppsChanged);
    if (_leased) _apps.release();
    _events?.cancel();
    super.dispose();
  }

  /// Holds the store's lease exactly while this row would draw icons, so a
  /// shell with the option off never opens a `GET_TREE` at all — the window
  /// events still arrive, they just wake nothing. The urgency flash is
  /// deliberately not part of this: it reads a flag off the `GET_WORKSPACES`
  /// reply the row fetches for itself, so it costs no round-trip to lease.
  void _syncLease() {
    final wanted = widget.config.showAppIcons;
    if (wanted == _leased) return;
    _leased = wanted;
    if (wanted) {
      _apps.acquire();
    } else {
      _apps.release();
    }
  }

  void _onAppsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onManagerChanged() {
    if (!mounted) return;
    // Rebuild even when the connection itself is unchanged — the connecting
    // flag drives the spinner.
    setState(_syncConnection);
  }

  /// Attaches to the manager's current connection, tearing down the listener on
  /// whichever connection it replaces. The manager drops a dead connection
  /// rather than reusing it, so every reconnect hands us a different instance.
  void _syncConnection() {
    final connection = _manager?.connection;
    if (identical(connection, _connection)) return;

    _events?.cancel();
    _events = null;
    _connection = connection;
    _workspaces = <WorkspaceResult>[];
    _outputs = <OutputResult>[];
    _workspacesSignature = '';
    _outputsSignature = '';
    // Every bar hands the store the same connection; it compares identity and
    // keeps one subscription for the machine.
    _apps.attach(connection);

    if (connection == null) return;
    _events = connection.listen(
      (Event event) {
        // A workspace event is the obvious trigger, and it carries urgency too:
        // miracle.dart 2.1 emits `workspace`/`urgent` alongside the window event
        // precisely so a bar watching workspaces sees it without walking the
        // tree. An output event is the less obvious one: miracle re-homes a
        // removed output's workspaces onto another output and emits no workspace
        // event saying so, which leaves the `workspace -> output` mapping this
        // row filters on stale.
        if (event is WorkspaceEvent || event is OutputEvent) {
          unawaited(_fetchWorkspaces());
        }
        // Only the output event: a workspace moving between monitors changes
        // nothing about which monitors exist, and the menu's second page is
        // built from the monitors alone.
        if (event is OutputEvent) {
          unawaited(_fetchOutputs());
        }
      },
      onError: (Object error) =>
          debugPrint('workspaces: undecodable IPC event: $error'),
    );
    unawaited(_fetchWorkspaces());
    unawaited(_fetchOutputs());
  }

  /// Re-reads the workspace row, coalescing a burst of events into one more
  /// round-trip.
  ///
  /// [WorkspaceAppsStore]'s shape, for [WorkspaceAppsStore]'s reasons and one
  /// more of its own: a request landing mid-flight is queued rather than
  /// dropped, because nothing here polls and a dropped refetch leaves the row
  /// stale until the next unrelated event — and only one reply is ever in
  /// flight, so the row cannot be walked backwards by an older one answering
  /// last.
  ///
  /// A reply from a connection that has since been replaced is discarded, and
  /// the loop re-reads [_connection] rather than returning, so a refetch
  /// [_syncConnection] queued behind a dead socket's round-trip is not lost
  /// with it.
  Future<void> _fetchWorkspaces() async {
    if (_workspacesInFlight) {
      _workspacesQueued = true;
      return;
    }
    _workspacesInFlight = true;
    try {
      do {
        _workspacesQueued = false;
        final connection = _connection;
        if (!mounted || connection == null) break;
        try {
          final workspaces = await connection.getWorkspaces();
          if (mounted && identical(_connection, connection)) {
            _updateWorkspaces(workspaces);
          } else {
            _workspacesQueued = true;
          }
        } catch (error) {
          debugPrint('workspaces: could not re-read the workspaces: $error');
        }
      } while (_workspacesQueued);
    } finally {
      _workspacesInFlight = false;
      _workspacesQueued = false;
    }
  }

  /// The same, for the monitors behind the menu's second page.
  ///
  /// A failure here costs that page and nothing else — the row still renders and
  /// still switches — so it is caught rather than left to surface as an
  /// unhandled rejection.
  Future<void> _fetchOutputs() async {
    if (_outputsInFlight) {
      _outputsQueued = true;
      return;
    }
    _outputsInFlight = true;
    try {
      do {
        _outputsQueued = false;
        final connection = _connection;
        if (!mounted || connection == null) break;
        try {
          final outputs = await connection.getOutputs();
          if (mounted && identical(_connection, connection)) {
            _updateOutputs(outputs);
          } else {
            _outputsQueued = true;
          }
        } catch (error) {
          debugPrint('workspaces: could not read the outputs: $error');
        }
      } while (_outputsQueued);
    } finally {
      _outputsInFlight = false;
      _outputsQueued = false;
    }
  }

  /// Installs a `GET_WORKSPACES` reply, rebuilding only when it draws
  /// differently.
  ///
  /// The store's "a read that finds nothing new must not notify" rule, applied
  /// where the read is the widget's own. The list is kept whatever the
  /// signature says — [_moveToOutput] reads the *globally* focused workspace
  /// out of it, which can be on the other monitor — and only the `setState` is
  /// guarded.
  void _updateWorkspaces(List<WorkspaceResult> workspaces) {
    if (!mounted) return;
    _workspaces = workspaces;
    final signature = workspaceRowSignature(workspaces);
    if (signature == _workspacesSignature) return;
    _workspacesSignature = signature;
    setState(() {});
  }

  void _updateOutputs(List<OutputResult> outputs) {
    if (!mounted) return;
    _outputs = outputs;
    final signature = outputMenuSignature(outputs);
    if (signature == _outputsSignature) return;
    _outputsSignature = signature;
    setState(() {});
  }

  /// Sets what [workspace] does with the windows opened on it next, then
  /// re-reads the row from miracle.
  ///
  /// **The re-read happens whether or not the command succeeded**, and the check
  /// mark in the menu is never moved optimistically: `workspace <n> policy float`
  /// is miracle's own, so a compositor older than it answers with a parse error,
  /// and a menu that had already moved would be reporting a policy nothing took.
  /// Moving it only once miracle has been asked again is what makes a refusal
  /// visible.
  ///
  /// A [policy] the workspace already has is dropped here rather than in the
  /// menu: the checked row stays tappable, and what it should cost is a closed
  /// menu, not a round-trip.
  ///
  /// The re-read is [MiracleConnection.getWorkspaces] — the same round-trip the
  /// row is built from — and it lands on the bar that was clicked. Another bar on
  /// the same output picks the change up from miracle's own `workspace` event,
  /// or, failing that, from the next one it sends.
  Future<void> _setPolicy(
    WorkspaceResult workspace,
    WindowPlacementPolicy policy,
  ) async {
    if (policy == workspace.policy) return;
    final connection = _connection;
    final selector = workspaceSelector(workspace);
    if (connection == null || selector == null) return;
    try {
      await connection.runOrThrow(
          MiracleCommand.workspacePolicy(policy, workspace: selector));
    } catch (error) {
      debugPrint('workspaces: could not set the workspace policy: $error');
    }
    await _reread(connection);
  }

  /// Moves [workspace] onto the output named [outputName].
  ///
  /// The command list is [moveWorkspaceCommands]'s, which is where the reason it
  /// is a *list* is written down: miracle's `move workspace to output` acts on
  /// the focused workspace, so a workspace that is not focused is focused, moved
  /// and left again. [MiracleConnection.runAll] sends the hops as one payload,
  /// so nothing can land between them.
  ///
  /// Re-read afterwards for [_setPolicy]'s reason, and with an extra one of its
  /// own: the workspace has left this bar's output, so the row that was clicked
  /// is one button shorter and cannot wait for an event to say so.
  Future<void> _moveToOutput(
    WorkspaceResult workspace,
    String outputName,
  ) async {
    final connection = _connection;
    final selector = workspaceSelector(workspace);
    if (connection == null || selector == null) return;
    final commands = moveWorkspaceCommands(
      selector: selector,
      output: outputName,
      focused: workspace.focused,
      // The workspace to come back to, which is the focused one — and null when
      // that is the one being moved, or when miracle named it nothing a command
      // could address.
      restore: workspaceSelector(
        _workspaces.firstWhere((ws) => ws.focused, orElse: () => workspace),
      ),
    );
    try {
      // One result per hop; a refusal part-way through is worth naming, because
      // it can leave the focus on the workspace that was to be moved.
      for (final result in await connection.runAll(commands)) {
        if (!result.success) {
          debugPrint('workspaces: could not move the workspace: '
              '${result.error ?? 'refused'}');
        }
      }
    } catch (error) {
      debugPrint('workspaces: could not move the workspace: $error');
    }
    await _reread(connection);
  }

  /// Re-reads the workspace row from [connection], if it is still this row's.
  ///
  /// The socket can die, or be replaced by a reconnect, while a command is in
  /// flight. Through [_fetchWorkspaces], so a command's re-read merges with
  /// whatever miracle's own event for that same command has already asked for
  /// rather than racing it — which is why this returns as soon as the read is
  /// *queued*, and no caller waits on the reply.
  Future<void> _reread(MiracleConnection connection) async {
    if (!mounted || !identical(_connection, connection)) return;
    await _fetchWorkspaces();
  }

  /// The placeholder that stands in for the workspace row while something it
  /// needs is still on its way. One button's worth of space, so the modules
  /// beside it do not shuffle sideways when the row arrives.
  Widget _pending(ThemeConfig theme) => Padding(
        padding: const EdgeInsets.all(4.0),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: LoadingIndicator(
              color: theme.foreground.withValues(alpha: 0.6),
              size: 12,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final connection = _connection;

    if (connection == null) {
      // The IPC connect is started after the shell's first frame, so for the
      // first moments the manager is not yet even *connecting*. Asking the
      // service registry as well is what keeps the retry button — which means
      // "this failed" — from flashing up before anything has been tried.
      final pending = (_manager?.connecting ?? false) ||
          ShellServicesScope.isLoading(context, ShellService.miracle);
      return pending
          ? _pending(theme)
          : const Padding(
              padding: EdgeInsets.all(4.0),
              child: _MiracleRetryButton(),
            );
    }

    // Bars paint before Wayland output enumeration finishes, so which display
    // this one is on may not be known yet — filtering on an unknown name would
    // render an empty row that then popped full. `WaylandOutput.name` is
    // non-nullable and starts empty, so an output bound but not yet named would
    // otherwise pass this guard and filter every workspace away.
    final outputName = DisplayScope.of(context)?.name;
    if (outputName == null || outputName.isEmpty) return _pending(theme);

    final visibleWorkspaces =
        _workspaces.where((ws) => ws.output == outputName).toList();
    final config = widget.config;
    final urgentPeriod = Duration(
        milliseconds: (config.urgentFlashSeconds * 1000).round());
    return Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          spacing: 4,
          children: visibleWorkspaces.map((workspace) {
            // Null for the one workspace miracle reported neither a number nor a
            // name for: there is no selector to send, so the button switches
            // nothing and carries no menu rather than spelling `null` into a
            // command.
            final selector = workspaceSelector(workspace);
            return _WorkspaceButton(
              key: ValueKey(workspace.num ?? workspace.name),
              backgroundColor: workspace.focused
                  ? theme.surfacePressed
                  : theme.workspaceBackground,
              hoverColor: theme.surfaceHover,
              pressedColor: theme.surfacePressed,
              urgent: shouldFlashWorkspace(config, workspace),
              urgentColor: theme.accent,
              urgentPeriod: urgentPeriod,
              onPressed: selector == null
                  ? null
                  : () => unawaited(
                        connection.run(MiracleCommand.workspace(selector)),
                      ),
              // The right-click menu. Built on demand rather than eagerly: a bar
              // with eight workspaces on it would otherwise be building eight
              // menus it will never show on every `GET_WORKSPACES` reply.
              //
              // `close` is called *before* the action, not after: every one of
              // these writes through miracle and re-reads the row, which rebuilds
              // this button — and, when the workspace leaves this output, removes
              // it — disposing the host that owns the popup mid-callback.
              menuBuilder: selector == null
                  ? null
                  : (context, close) => WorkspaceMenu(
                        workspace: workspace,
                        outputs: _outputs,
                        showPolicy: shouldShowPolicyToggle(config, workspace),
                        onSetPolicy: (policy) {
                          close();
                          unawaited(_setPolicy(workspace, policy));
                        },
                        onMoveToOutput: (outputName) {
                          close();
                          unawaited(_moveToOutput(workspace, outputName));
                        },
                      ),
              child: _WorkspaceLabel(
                label: workspace.name ?? workspace.num?.toString() ?? '?',
                appIds:
                    config.showAppIcons ? _apps.appIdsFor(workspace) : const [],
                config: config,
                foreground: theme.foreground,
              ),
            );
          }).toList(),
        ));
  }
}

/// One workspace button's content: its number or name, and the icons of what is
/// open on it.
///
/// The label stays whatever the rest does — it is the number the user switches
/// by, and an empty workspace with its icons switched off has nothing else to
/// render.
class _WorkspaceLabel extends StatelessWidget {
  const _WorkspaceLabel({
    required this.label,
    required this.appIds,
    required this.config,
    required this.foreground,
  });

  final String label;
  final List<String> appIds;
  final WorkspacesConfig config;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: TextStyle(color: foreground));
    if (appIds.isEmpty) return text;

    final shown = appIds.length <= config.maxIcons
        ? appIds
        : appIds.take(config.maxIcons).toList();
    final hidden = appIds.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        text,
        for (final appId in shown)
          _WorkspaceAppIconView(
            // Keyed by app_id: the row is rebuilt whenever the tree moves, and
            // without a key an icon would animate into a different app's slot.
            key: ValueKey(appId),
            appId: appId,
            size: config.iconSize,
            foreground: foreground,
          ),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: TextStyle(
              color: foreground.withValues(alpha: 0.7),
              fontSize: ShellFontSizes.caption,
            ),
          ),
      ],
    );
  }
}

/// One application icon in the workspace row.
class _WorkspaceAppIconView extends StatelessWidget {
  const _WorkspaceAppIconView({
    super.key,
    required this.appId,
    required this.size,
    required this.foreground,
  });

  final String appId;
  final int size;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    // Memoised in the store: this runs per icon per build, and a miss is a GIO
    // lookup.
    final icon = WorkspaceAppsStore.instance.iconFor(appId);
    return AppIconImage(
      iconName: icon.iconName,
      name: icon.name,
      size: size,
      foreground: foreground,
    );
  }
}

/// Stands in for the workspace row while the shell has no Miracle connection.
/// One click retries for every bar at once — the connection is shell-wide.
class _MiracleRetryButton extends StatefulWidget {
  const _MiracleRetryButton();

  @override
  State<_MiracleRetryButton> createState() => _MiracleRetryButtonState();
}

class _MiracleRetryButtonState extends State<_MiracleRetryButton>
    with PopupHost<_MiracleRetryButton> {
  bool _hovered = false;

  void _openTooltip(BuildContext context) {
    if (isPopupOpen) return;
    final error = MiracleScope.of(context).lastError;
    openBarPopup(
      context,
      child: ThemeProvider(
        child: TooltipLabel(
          text: error == null
              ? 'Not connected to Miracle — click to retry'
              : 'Not connected to Miracle — click to retry\n$error',
        ),
      ),
      preferredConstraints: const BoxConstraints(maxWidth: 260, maxHeight: 64),
      // A hover label displaces nothing, and never attaches to the bar — see
      // the dock's tooltip.
      policy: TransientPolicy.tooltip,
      attach: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hovered) _openTooltip(context);
        });
      },
      onExit: (_) {
        setState(() => _hovered = false);
        closePopup();
      },
      child: _WorkspaceButton(
        backgroundColor: theme.workspaceBackground,
        hoverColor: theme.surfaceHover,
        pressedColor: theme.surfacePressed,
        onPressed: () {
          closePopup();
          MiracleScope.of(context).connect();
        },
        child: FaIcon(
          FontAwesomeIcons.arrowsRotate,
          size: 10,
          color: theme.foreground,
        ),
      ),
    );
  }
}

class _WorkspaceButton extends StatefulWidget {
  const _WorkspaceButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor = const Color(0xFF3A3A3A),
    this.hoverColor = const Color(0xFF4A4A4A),
    this.pressedColor = const Color(0xFF2A2A2A),
    this.urgent = false,
    this.urgentColor = const Color(0xFF853953),
    this.urgentPeriod = const Duration(seconds: 5),
    this.menuBuilder,
  });

  /// Fixed, not parameters: every call site took the defaults.
  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 4, vertical: 4);
  static const double _borderRadius = 6;

  final VoidCallback? onPressed;
  final Widget child;
  final Color backgroundColor;
  final Color hoverColor;
  final Color pressedColor;

  /// Whether the button breathes in [urgentColor] to say something on this
  /// workspace wants looking at.
  final bool urgent;

  /// The colour it breathes to at the top of each cycle.
  final Color urgentColor;

  /// How long one breath takes.
  final Duration urgentPeriod;

  /// The card a right-click opens, given a callback that closes it again.
  ///
  /// A builder rather than a widget so a bar full of workspaces builds the one
  /// menu it is asked for instead of one per button per `GET_WORKSPACES` reply,
  /// and nullable because two of this button's users have no menu: the retry
  /// button that stands in for the whole row, and the one workspace miracle
  /// named nothing a command could address.
  final Widget Function(BuildContext context, VoidCallback close)? menuBuilder;

  @override
  State<_WorkspaceButton> createState() => _WorkspaceButtonState();
}

final Module workspacesModule = Module.simple(
  configKey: 'workspaces',
  fromMap: WorkspacesConfig.fromMap,
  builder: (context, config) => Workspaces(config: config),
);

class _WorkspaceButtonState extends State<_WorkspaceButton>
    with PopupHost<_WorkspaceButton> {
  bool _hovered = false;
  bool _pressed = false;

  /// Opens the right-click menu under this button.
  ///
  /// [closePopup] first, because the pointer-down that got here has already
  /// asked the coordinator to dismiss whatever was open — including this
  /// button's own menu, which is what makes a second right-click a re-open
  /// rather than a second surface. The post-frame hop is the dock's, for the
  /// dock's reason: the close is synchronous but the window it dropped is on
  /// screen for another frame, and `openBarPopup` measures this button's box
  /// against the panel to place the new one.
  void _openMenu(BuildContext context) {
    final menuBuilder = widget.menuBuilder;
    if (menuBuilder == null) return;
    closePopup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openBarPopup(
        context,
        // Loose: the menu sizes to its content (see [DesktopMenuCard]). Tall
        // enough for the two placement rows, the move row and a page of
        // outputs; wide enough for a connector name and a monitor's model.
        preferredConstraints:
            const BoxConstraints(maxWidth: 320, maxHeight: 320),
        // The card lays out under its own FlutterView, so it carries its own
        // theme — `ThemeScope` is an InheritedWidget and cannot span views.
        child: ThemeProvider(
          child: menuBuilder(context, closePopup),
        ),
      );
    });
  }

  @override
  void dispose() {
    // The mixin answers the awaiting close and tears the window down; a popup
    // outliving the button that opened it is what [PopupHost] exists to stop.
    closePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;

    Color color = widget.backgroundColor;
    if (!enabled) {
      color = color.withValues(alpha: 0.5);
    } else if (_pressed) {
      color = widget.pressedColor;
    } else if (_hovered) {
      color = widget.hoverColor;
    }

    const radius =
        BorderRadius.all(Radius.circular(_WorkspaceButton._borderRadius));
    final decoration = BoxDecoration(color: color, borderRadius: radius);

    final content = Padding(
      padding: _WorkspaceButton._padding,
      // A *minimum*, not a fixed square: a workspace carrying app icons is
      // as wide as its icons, and one carrying none still reads as the
      // 16px dot every workspace used to be. `widthFactor`/`heightFactor`
      // are what keep the Center sized to its child rather than expanding
      // to the panel's own width.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: widget.child,
        ),
      ),
    );

    // The flash is wrapped on only while urgent, so the ticker, the extra
    // layers and the wash exist exactly while something is asking to be looked
    // at — an idle bar is the bar it was before this feature. The fill is
    // handed over separately there because the wash goes *between* the two:
    // over the button's own colour, and under its number.
    final Widget surface = widget.urgent
        ? UrgencyFlash(
            color: widget.urgentColor,
            period: widget.urgentPeriod,
            borderRadius: radius,
            background: AnimatedContainer(
              duration: ShellDurations.fast,
              decoration: decoration,
            ),
            child: content,
          )
        // Boundaried for the flash's reason, on the path that is hit far more
        // often than the flash ever is. `AnimatedContainer` tweens the fill
        // whenever this button gains or loses the focus ring — and under
        // focus-follows-mouse, a pointer crossing the seam between two monitors
        // retints a button on *each* of them, every crossing. A bar has no
        // repaint boundary of its own, so without this each frame of that tween
        // re-records the whole panel picture and damages the whole output; waggle
        // the pointer across the seam and the two bars never settle. The urgent
        // branch is already inside [UrgencyFlash]'s own boundary.
        : RepaintBoundary(
            child: AnimatedContainer(
              duration: ShellDurations.fast,
              decoration: decoration,
              child: content,
            ),
          );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // On tap-*down*, the way every popup toggle in the bar opens: the same
        // pointer-down the coordinator dismisses on, so the menu cannot be
        // opened by a press that has yet to close what is already up.
        onSecondaryTapDown:
            widget.menuBuilder == null ? null : (_) => _openMenu(context),
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: surface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The urgency flash
// ---------------------------------------------------------------------------

/// Where in one breath the shell is at [now], as a fraction of [period].
///
/// Read off the **wall clock**, which is what makes every urgent button agree.
/// Each bar is its own FlutterView with its own ticker, so two monitors — or two
/// workspaces going urgent a second apart — would otherwise breathe out of step,
/// and a row of dots pulsing at random phases reads as a rendering fault rather
/// than as one alarm. Offsetting each controller by the phase it *started* at
/// cancels its own start time out of the sum.
@visibleForTesting
double urgencyFlashPhase(DateTime now, Duration period) {
  final millis = period.inMilliseconds;
  // A degenerate period cannot be divided by; the caller clamps, so this is
  // only reachable from a test.
  if (millis <= 0) return 0;
  return (now.millisecondsSinceEpoch % millis) / millis;
}

/// How strongly the flash colour is laid over the button at [t] of a breath.
///
/// A raised cosine, so the two ends are *still* rather than merely slow: a
/// linear ping-pong reverses at a corner, and a corner is the one thing in a
/// slow animation the eye reliably catches — which puts the emphasis on the
/// moment the flash is quietest instead of on the colour it is fading up to.
/// Resting at 0 (and not at some floor) is what keeps an urgent workspace
/// passing through exactly the colour its neighbours are, once a breath, so the
/// flash reads as the same button changing rather than as a different one.
@visibleForTesting
double urgencyFlashWash(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * t);

/// Breathes [color] across [background], very slowly, under [child], for as long
/// as it is in the tree.
///
/// Deliberately three layers rather than a lerp of one fill: the button goes on
/// animating its own hover and press colours exactly as it does at rest, and
/// [child] — the number the user switches by — is painted last and never
/// touched. A wash over the whole button is the obvious shape and it *erases the
/// label* at the top of every breath, which reads as the bar glitching.
///
/// Four things a change here has to keep true:
///
/// - **Nothing about it exists at rest.** The caller wraps this only while the
///   workspace is urgent, so the ticker is created when the alarm is raised and
///   disposed when it clears. An always-mounted version gated on a flag would be
///   a `Ticker` per workspace button per monitor.
/// - **[child] is the one unpositioned layer, and it is listed last.** It sizes
///   the surface, and being last is what puts the wash under it rather than over
///   it — reordering for the paint would take the sizing with it.
/// - **The repaint stops here, twice.** A bar has no repaint boundary of its own,
///   so a colour changing every frame in one dot would re-record the whole panel
///   picture sixty times a second. The outer boundary keeps the damage inside
///   this button; the inner one keeps its label and app icons out of the layer
///   that is actually repainting.
/// - **The wash never takes a click.** `RenderDecoratedBox.hitTestSelf` answers
///   for any non-null fill, so a full-size box would swallow the tap that
///   switches workspace — `HoverRegion`'s trap from the other side.
class UrgencyFlash extends StatefulWidget {
  const UrgencyFlash({
    super.key,
    required this.color,
    required this.period,
    required this.borderRadius,
    required this.background,
    required this.child,
  });

  /// The colour at the top of each breath — the theme's, so a flash is the
  /// shell's own accent rather than a red this file chose.
  final Color color;

  /// One full breath: out of the resting colour, up to [color], and back.
  final Duration period;

  /// The button's own corner rounding, so the wash stops where it does.
  final BorderRadius borderRadius;

  /// The button's resting fill, which the wash is laid over. Sized by [child].
  final Widget background;

  /// The button's content. Sizes the surface, and is painted over the wash.
  final Widget child;

  @override
  State<UrgencyFlash> createState() => _UrgencyFlashState();
}

class _UrgencyFlashState extends State<UrgencyFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);

  /// Where in the breath the wall clock was when this one started; see
  /// [urgencyFlashPhase].
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(UrgencyFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A `[modules.workspaces]` edit is the only thing that moves this, and
    // re-deriving the phase is what keeps the new period aligned with every
    // other bar's — which is the whole reason the phase exists.
    if (widget.period != oldWidget.period) {
      _controller.duration = widget.period;
      _start();
    }
  }

  void _start() {
    _phase = urgencyFlashPhase(DateTime.now(), widget.period);
    // Unbounded and unreversed: the breath's shape is [urgencyFlashWash]'s, so
    // the controller is a bare 0..1 sawtooth the phase can be added to. A
    // `reverse: true` repeat would run at twice this period on the way back
    // and leave nothing to add an offset to.
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        // Non-directional, so this needs no `Directionality` of its own:
        // `Positioned.fill` supplies all four edges, and the alignment is the
        // only other thing in a `Stack` that would ask for one.
        alignment: Alignment.topLeft,
        children: [
          Positioned.fill(child: widget.background),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: widget.color.a *
                          urgencyFlashWash((_controller.value + _phase) % 1.0),
                    ),
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          ),
          // Last, so the wash goes under it; unpositioned, so it is what sizes
          // the stack; and boundaried, so the wash repainting does not
          // re-record the label and the app icons.
          RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }
}
