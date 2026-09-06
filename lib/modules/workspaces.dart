import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/modules/workspace_apps.dart';
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
  MiracleManager? _manager;
  MiracleConnection? _connection;
  StreamSubscription<Event>? _events;

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
          connection.getWorkspaces().then(_updateWorkspaces);
        }
      },
      onError: (Object error) =>
          debugPrint('workspaces: undecodable IPC event: $error'),
    );
    connection.getWorkspaces().then(_updateWorkspaces);
  }

  void _updateWorkspaces(List<WorkspaceResult> workspaces) {
    if (!mounted) return;
    setState(() {
      _workspaces = workspaces;
    });
  }

  /// Flips [workspace] between tiling what is opened on it next and floating
  /// it, then re-reads the row from miracle.
  ///
  /// **The re-read happens whether or not the command succeeded**, and the glyph
  /// is never flipped optimistically: `workspace <n> policy float` is miracle's
  /// own, so a compositor older than it answers with a parse error, and a toggle
  /// that had already moved would be reporting a policy nothing took. Flipping
  /// only once miracle has been asked again is what makes a refusal visible as
  /// the button snapping back.
  ///
  /// The re-read is [MiracleConnection.getWorkspaces] — the same round-trip the
  /// row is built from — and it lands on the bar that was clicked. Another bar on
  /// the same output picks the change up from miracle's own `workspace` event,
  /// or, failing that, from the next one it sends.
  Future<void> _togglePolicy(WorkspaceResult workspace) async {
    final connection = _connection;
    final selector = workspaceSelector(workspace);
    if (connection == null || selector == null) return;
    try {
      await connection.runOrThrow(MiracleCommand.workspacePolicy(
        nextWorkspacePolicy(workspace.policy),
        workspace: selector,
      ));
    } catch (error) {
      debugPrint('workspaces: could not set the workspace policy: $error');
    }
    // The socket can die, or be replaced by a reconnect, while the command is
    // in flight; `_updateWorkspaces` answers for the widget being gone.
    if (!mounted || !identical(_connection, connection)) return;
    try {
      _updateWorkspaces(await connection.getWorkspaces());
    } catch (error) {
      debugPrint('workspaces: could not re-read the workspaces: $error');
    }
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
            // nothing and carries no policy toggle rather than spelling `null`
            // into a command.
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
              child: _WorkspaceLabel(
                label: workspace.name ?? workspace.num?.toString() ?? '?',
                appIds:
                    config.showAppIcons ? _apps.appIdsFor(workspace) : const [],
                config: config,
                foreground: theme.foreground,
                // Null on every button but the focused one; see
                // [shouldShowPolicyToggle].
                policy: shouldShowPolicyToggle(config, workspace)
                    ? workspace.policy
                    : null,
                onTogglePolicy: () => unawaited(_togglePolicy(workspace)),
              ),
            );
          }).toList(),
        ));
  }
}

/// One workspace button's content: its number or name, the icons of what is
/// open on it, and — on the focused workspace alone — the tile/float toggle.
///
/// The label stays whatever the rest does — it is the number the user switches
/// by, and an empty workspace with the toggle switched off has nothing else to
/// render.
class _WorkspaceLabel extends StatelessWidget {
  const _WorkspaceLabel({
    required this.label,
    required this.appIds,
    required this.config,
    required this.foreground,
    required this.policy,
    required this.onTogglePolicy,
  });

  final String label;
  final List<String> appIds;
  final WorkspacesConfig config;
  final Color foreground;

  /// The workspace's window placement policy, or null when this button is not
  /// the one that carries the toggle. See [shouldShowPolicyToggle].
  final WindowPlacementPolicy? policy;

  /// Flips [policy]. Only reached while [policy] is non-null.
  final VoidCallback onTogglePolicy;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: TextStyle(color: foreground));
    final policy = this.policy;
    if (appIds.isEmpty && policy == null) return text;

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
        // Last, so the toggle sits at the trailing edge of the button whether or
        // not the workspace is carrying icons — a control that moved to the
        // middle of the row as windows opened would be a control nobody could
        // aim at.
        if (policy != null)
          WorkspacePolicyToggle(policy: policy, onToggle: onTogglePolicy),
      ],
    );
  }
}

/// The focused workspace's tile/float switch.
///
/// Nested inside `_WorkspaceButton`'s own detector on purpose: this *is* a
/// control on that button, and the gesture arena resolves it correctly by
/// construction — hit testing runs deepest-first, so this recognizer enters the
/// arena before the button's and wins the sweep, which leaves the workspace
/// switch untriggered by a press on the glyph. The button's own tap-down still
/// draws its pressed fill and is cancelled when this one wins, which is the
/// feedback a press wants anyway. `test/workspace_policy_test.dart` is what
/// keeps that true, which is why this widget is public rather than private.
class WorkspacePolicyToggle extends StatelessWidget {
  const WorkspacePolicyToggle({
    super.key,
    required this.policy,
    required this.onToggle,
  });

  /// The pointer target, which is also the hover box — one rect, per
  /// [HoverRegion].
  ///
  /// Below [ShellSizes.iconButtonDense] because the bar's height forces it, and
  /// only just: a default 32px panel is spent exactly by the row's 8px padding,
  /// the button's 8px padding and its 16px minimum content box, so a taller box
  /// here grows the workspace row past the bar it is drawn in.
  static const double _box = 16;

  /// The glyph inside that box. Never the target — see [ShellSizes].
  static const double _glyph = 9;

  final WindowPlacementPolicy policy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final bool floating = policy == WindowPlacementPolicy.float;
    return RepaintBoundary(
      // A bar has no repaint boundary of its own, so without this one the
      // pointer crossing a 16px glyph would re-record the whole panel picture
      // and damage the whole output.
      child: HoverRegion(
        onTap: onToggle,
        builder: (context, hovered) => SizedBox(
          width: _box,
          height: _box,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : null,
              borderRadius: BorderRadius.circular(ShellRadii.barButton),
            ),
            child: Center(
              child: FaIcon(
                // Two overlapping windows against a grid of cells: the picture
                // is what the *workspace* will do with the next window, not
                // what the button does when pressed.
                floating
                    ? FontAwesomeIcons.solidClone
                    : FontAwesomeIcons.tableCells,
                size: _glyph,
                // Floating is the departure from miracle's default, so it is the
                // state that carries the accent; tiling reads as the quiet one.
                color: floating
                    ? theme.accent
                    : theme.foreground.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
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

  @override
  State<_WorkspaceButton> createState() => _WorkspaceButtonState();
}

final Module workspacesModule = Module.simple(
  configKey: 'workspaces',
  fromMap: WorkspacesConfig.fromMap,
  builder: (context, config) => Workspaces(config: config),
);

class _WorkspaceButtonState extends State<_WorkspaceButton> {
  bool _hovered = false;
  bool _pressed = false;

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
        : AnimatedContainer(
            duration: ShellDurations.fast,
            decoration: decoration,
            child: content,
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
