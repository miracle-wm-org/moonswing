// ignore_for_file: library_private_types_in_public_api

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/overlay/settings/display_layout.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:wayland/wayland.dart';

// ---------------------------------------------------------------------------
// Protocol: zwlr_output_mode_v1
// ---------------------------------------------------------------------------

class ZwlrOutputModeV1 extends WaylandObject {
  @override
  String get interfaceName => 'zwlr_output_mode_v1';

  int width = 0;
  int height = 0;
  int refreshMHz = 0;
  bool preferred = false;
  bool finished = false;

  final VoidCallback onChanged;

  ZwlrOutputModeV1(super.client, super.id, {required this.onChanged});

  String get label {
    final hz = refreshMHz / 1000.0;
    return '$width×$height @ ${hz.toStringAsFixed(1)} Hz';
  }

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0:
        final b = WaylandReadBuffer(payload);
        width = b.readInt();
        height = b.readInt();
        onChanged();
        return true;
      case 1:
        refreshMHz = WaylandReadBuffer(payload).readInt();
        onChanged();
        return true;
      case 2:
        preferred = true;
        onChanged();
        return true;
      case 3:
        finished = true;
        onChanged();
        return true;
      default:
        return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Protocol: zwlr_output_head_v1
// ---------------------------------------------------------------------------

class ZwlrOutputHeadV1 extends WaylandObject {
  @override
  String get interfaceName => 'zwlr_output_head_v1';

  String name = '';
  String description = '';
  String make = '';
  String model = '';
  String serialNumber = '';
  int physicalWidth = 0;
  int physicalHeight = 0;
  bool enabled = false;
  int positionX = 0;
  int positionY = 0;
  int transform = 0;
  double scale = 1.0;
  bool finished = false;

  final Map<int, ZwlrOutputModeV1> modes = {};
  ZwlrOutputModeV1? currentMode;

  final VoidCallback onChanged;

  ZwlrOutputHeadV1(super.client, super.id, {required this.onChanged});

  List<ZwlrOutputModeV1> get sortedModes {
    final list = modes.values.where((m) => !m.finished).toList();
    list.sort((a, b) {
      if (a.preferred && !b.preferred) return -1;
      if (!a.preferred && b.preferred) return 1;
      final ap = a.width * a.height;
      final bp = b.width * b.height;
      if (ap != bp) return bp.compareTo(ap);
      return b.refreshMHz.compareTo(a.refreshMHz);
    });
    return list;
  }

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0:
        name = WaylandReadBuffer(payload).readString();
        onChanged();
        return true;
      case 1:
        description = WaylandReadBuffer(payload).readString();
        onChanged();
        return true;
      case 2:
        final b = WaylandReadBuffer(payload);
        physicalWidth = b.readInt();
        physicalHeight = b.readInt();
        onChanged();
        return true;
      case 3:
        final modeId = WaylandReadBuffer(payload).readUint();
        final mode = ZwlrOutputModeV1(client, modeId, onChanged: onChanged);
        modes[modeId] = mode;
        onChanged();
        return true;
      case 4:
        enabled = WaylandReadBuffer(payload).readUint() != 0;
        onChanged();
        return true;
      case 5:
        final modeId = WaylandReadBuffer(payload).readUint();
        currentMode = modes[modeId];
        onChanged();
        return true;
      case 6:
        final b = WaylandReadBuffer(payload);
        positionX = b.readInt();
        positionY = b.readInt();
        onChanged();
        return true;
      case 7:
        transform = WaylandReadBuffer(payload).readInt();
        onChanged();
        return true;
      case 8:
        scale = WaylandReadBuffer(payload).readFixed();
        onChanged();
        return true;
      case 9:
        finished = true;
        onChanged();
        return true;
      case 10:
        make = WaylandReadBuffer(payload).readString();
        onChanged();
        return true;
      case 11:
        model = WaylandReadBuffer(payload).readString();
        onChanged();
        return true;
      case 12:
        serialNumber = WaylandReadBuffer(payload).readString();
        onChanged();
        return true;
      default:
        return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Protocol: zwlr_output_manager_v1
// ---------------------------------------------------------------------------

class ZwlrOutputManagerV1 extends WaylandObject {
  @override
  String get interfaceName => 'zwlr_output_manager_v1';

  final List<ZwlrOutputHeadV1> heads = [];
  // Null until the first done() event arrives; 0 is a valid serial value.
  int? serial;

  final VoidCallback onChanged;

  ZwlrOutputManagerV1(super.client, super.id, {required this.onChanged});

  ZwlrOutputConfigurationV1 createConfiguration({
    required VoidCallback onSucceeded,
    required VoidCallback onFailed,
    required VoidCallback onCancelled,
  }) {
    final newId = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeUint(newId);
    payload.writeUint(serial ?? 0);
    client.sendRequest(id, 0, payload.data);
    return ZwlrOutputConfigurationV1(
      client,
      newId,
      onSucceeded: onSucceeded,
      onFailed: onFailed,
      onCancelled: onCancelled,
    );
  }

  void stop() {
    client.sendRequest(id, 1);
  }

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0:
        final headId = WaylandReadBuffer(payload).readUint();
        final head = ZwlrOutputHeadV1(client, headId, onChanged: onChanged);
        heads.add(head);
        onChanged();
        return true;
      case 1:
        serial = WaylandReadBuffer(payload).readUint();
        heads.removeWhere((h) => h.finished);
        onChanged();
        return true;
      case 2:
        onChanged();
        return true;
      default:
        return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Protocol: zwlr_output_configuration_v1
// ---------------------------------------------------------------------------

class ZwlrOutputConfigurationV1 extends WaylandObject {
  @override
  String get interfaceName => 'zwlr_output_configuration_v1';

  final VoidCallback onSucceeded;
  final VoidCallback onFailed;
  final VoidCallback onCancelled;

  ZwlrOutputConfigurationV1(
    super.client,
    super.id, {
    required this.onSucceeded,
    required this.onFailed,
    required this.onCancelled,
  });

  ZwlrOutputConfigurationHeadV1 enableHead(ZwlrOutputHeadV1 head) {
    final newId = client.getNextId();
    final payload = WaylandWriteBuffer();
    payload.writeUint(newId);
    payload.writeObject(head);
    client.sendRequest(id, 0, payload.data);
    return ZwlrOutputConfigurationHeadV1(client, newId);
  }

  void disableHead(ZwlrOutputHeadV1 head) {
    final payload = WaylandWriteBuffer();
    payload.writeObject(head);
    client.sendRequest(id, 1, payload.data);
  }

  void apply() => client.sendRequest(id, 2);
  void test() => client.sendRequest(id, 3);
  void destroy() => client.sendRequest(id, 4);

  @override
  bool processEvent(int code, Uint8List payload) {
    switch (code) {
      case 0:
        onSucceeded();
        return true;
      case 1:
        onFailed();
        return true;
      case 2:
        onCancelled();
        return true;
      default:
        return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Protocol: zwlr_output_configuration_head_v1
// ---------------------------------------------------------------------------

class ZwlrOutputConfigurationHeadV1 extends WaylandObject {
  @override
  String get interfaceName => 'zwlr_output_configuration_head_v1';

  ZwlrOutputConfigurationHeadV1(super.client, super.id);

  void setMode(ZwlrOutputModeV1 mode) {
    final payload = WaylandWriteBuffer();
    payload.writeObject(mode);
    client.sendRequest(id, 0, payload.data);
  }

  void setPosition(int x, int y) {
    final payload = WaylandWriteBuffer();
    payload.writeInt(x);
    payload.writeInt(y);
    client.sendRequest(id, 2, payload.data);
  }

  void setTransform(int transform) {
    final payload = WaylandWriteBuffer();
    payload.writeInt(transform);
    client.sendRequest(id, 3, payload.data);
  }

  // Encode as Wayland wl_fixed_t: 24.8 fixed-point stored as uint32.
  void setScale(double scale) {
    final payload = WaylandWriteBuffer();
    payload.writeUint((scale * 256).round());
    client.sendRequest(id, 4, payload.data);
  }
}

// ---------------------------------------------------------------------------
// Pending edit state
// ---------------------------------------------------------------------------

/// What the compositor last told us about a head.
///
/// Compared against the head's current values to tell a genuine external
/// reconfiguration apart from the echo — or the silence — that follows our own
/// apply. See `_DisplaySettingsPageState._reconcileEdits`.
class _HeadState {
  const _HeadState({
    required this.enabled,
    required this.modeId,
    required this.scale,
    required this.transform,
    required this.positionX,
    required this.positionY,
  });

  factory _HeadState.fromHead(ZwlrOutputHeadV1 head) => _HeadState(
        enabled: head.enabled,
        modeId: head.currentMode?.id,
        scale: head.scale,
        transform: head.transform,
        positionX: head.positionX,
        positionY: head.positionY,
      );

  final bool enabled;
  final int? modeId;
  final double scale;
  final int transform;
  final int positionX;
  final int positionY;

  @override
  bool operator ==(Object other) =>
      other is _HeadState &&
      other.enabled == enabled &&
      other.modeId == modeId &&
      (other.scale - scale).abs() < 0.001 &&
      other.transform == transform &&
      other.positionX == positionX &&
      other.positionY == positionY;

  // scale is compared with a tolerance, so it stays out of the hash.
  @override
  int get hashCode =>
      Object.hash(enabled, modeId, transform, positionX, positionY);
}

class _DisplayEdit {
  bool enabled;
  ZwlrOutputModeV1? selectedMode;
  double scale;
  int transform;
  int positionX;
  int positionY;

  _DisplayEdit({
    required this.enabled,
    this.selectedMode,
    required this.scale,
    required this.transform,
    required this.positionX,
    required this.positionY,
  });

  factory _DisplayEdit.fromHead(ZwlrOutputHeadV1 head) => _DisplayEdit(
        enabled: head.enabled,
        selectedMode: head.currentMode,
        scale: head.scale,
        transform: head.transform,
        positionX: head.positionX,
        positionY: head.positionY,
      );

  _DisplayEdit copyWith({
    bool? enabled,
    ZwlrOutputModeV1? selectedMode,
    bool clearMode = false,
    double? scale,
    int? transform,
    int? positionX,
    int? positionY,
  }) =>
      _DisplayEdit(
        enabled: enabled ?? this.enabled,
        selectedMode: clearMode ? null : (selectedMode ?? this.selectedMode),
        scale: scale ?? this.scale,
        transform: transform ?? this.transform,
        positionX: positionX ?? this.positionX,
        positionY: positionY ?? this.positionY,
      );
}

// ---------------------------------------------------------------------------
// DisplaySettingsPage
// ---------------------------------------------------------------------------

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  _DisplaySettingsPageState createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  WaylandClient? _waylandClient;
  ZwlrOutputManagerV1? _manager;
  bool _loaded = false;
  String? _error;
  final Map<int, _DisplayEdit> _edits = {};
  final Map<int, _HeadState> _lastHead = {};
  /// The user has edits this session's apply has not committed yet.
  bool _dirty = false;
  bool _applying = false;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final client = WaylandClient();
      await client.connect();
      if (!mounted) {
        await client.close();
        return;
      }
      _waylandClient = client;

      WaylandRegistry? registry;
      registry = client.getRegistry(
        onGlobal: (name, interface, version) {
          if (interface == 'zwlr_output_manager_v1') {
            final boundId =
                registry!.bind(name, interface, math.min(version, 2));
            _manager = ZwlrOutputManagerV1(
              client,
              boundId,
              onChanged: _onManagerChanged,
            );
          }
        },
      );
      // Sync so we know all registry globals have been advertised.
      // If zwlr_output_manager_v1 wasn't announced, we can show an error.
      client.sync((_) {
        if (!mounted) return;
        if (_manager == null) {
          setState(() =>
              _error = 'Display management not supported by this compositor');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to connect: $e');
    }
  }

  void _onManagerChanged() {
    if (!mounted) return;
    final manager = _manager;
    // serial is null until the first done() event; 0 is a valid serial value.
    if (manager == null || manager.serial == null) return;
    setState(() => _loaded = true);
  }

  /// Fold the compositor's view of the heads into `_edits`, which is what the
  /// diagram and the cards render from.
  ///
  /// An entry is (re)seeded only when the head itself moved since we last
  /// looked. What a *successful* apply put on screen is already in `_edits`, and
  /// a compositor that answers it by echoing nothing — or by echoing the
  /// positions it held before the apply — must not be allowed to drag the
  /// diagram back to the arrangement the user just left. Re-seeding
  /// unconditionally is the bug this method exists to prevent; a `putIfAbsent`
  /// that never re-seeds is the one before it, which is why an external change
  /// (hotplug, another tool) still lands here.
  void _reconcileEdits() {
    final manager = _manager;
    if (manager == null) return;
    final live = <int>{};
    for (final head in manager.heads) {
      live.add(head.id);
      final state = _HeadState.fromHead(head);
      final previous = _lastHead[head.id];
      _lastHead[head.id] = state;
      // Unchanged since we last looked, or the user is mid-edit: their values
      // stand. A first sighting always seeds.
      if (previous != null && (previous == state || _dirty)) continue;
      _edits[head.id] = _DisplayEdit.fromHead(head);
    }
    _edits.removeWhere((id, _) => !live.contains(id));
    _lastHead.removeWhere((id, _) => !live.contains(id));
  }

  Future<void> _apply() async {
    final manager = _manager;
    if (manager == null || _applying) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });

    ZwlrOutputConfigurationV1? config;
    config = manager.createConfiguration(
      onSucceeded: () {
        config?.destroy();
        if (!mounted) return;
        // `_edits` is what the compositor now holds — keep it. Clearing it and
        // re-reading the heads is what used to put the old arrangement back.
        setState(() {
          _applying = false;
          _dirty = false;
        });
      },
      onFailed: () {
        config?.destroy();
        if (!mounted) return;
        setState(() {
          _applyError = 'Configuration failed';
          _applying = false;
        });
      },
      onCancelled: () {
        config?.destroy();
        if (!mounted) return;
        setState(() {
          _applyError = 'Configuration was cancelled';
          _applying = false;
        });
      },
    );

    for (final head in manager.heads) {
      final edit = _edits[head.id];
      if (edit == null) continue;
      if (edit.enabled) {
        final configHead = config.enableHead(head);
        final mode = edit.selectedMode ?? head.currentMode;
        if (mode != null) configHead.setMode(mode);
        configHead.setScale(edit.scale);
        configHead.setTransform(edit.transform);
        configHead.setPosition(edit.positionX, edit.positionY);
      } else {
        config.disableHead(head);
      }
    }

    config.apply();
  }

  @override
  void dispose() {
    _manager?.stop();
    _waylandClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_error != null) return _buildError(theme);
    if (!_loaded) return _buildLoading(theme);
    _reconcileEdits();
    return _buildLoaded(theme);
  }

  Widget _buildHeader(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Text(
        'Display',
        style: TextStyle(
          fontSize: 16,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        const Expanded(
          child: Center(child: LoadingIndicator(size: 22)),
        ),
      ],
    );
  }

  Widget _buildError(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Center(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: theme.accent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoaded(ThemeConfig theme) {
    final manager = _manager!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (manager.heads.isNotEmpty)
                _DisplayDiagram(
                  heads: manager.heads,
                  edits: _edits,
                  onPositionsChanged: (positions) {
                    setState(() {
                      _dirty = true;
                      positions.forEach((headId, pos) {
                        final edit = _edits[headId];
                        if (edit != null) {
                          _edits[headId] = edit.copyWith(
                            positionX: pos.x,
                            positionY: pos.y,
                          );
                        }
                      });
                    });
                  },
                ),
              Container(height: 1, color: theme.divider),
              Expanded(
                child: manager.heads.isEmpty
                    ? Center(
                        child: Text(
                          'No displays detected',
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: theme.fontFamily,
                            color: theme.popupForeground.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: manager.heads.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final head = manager.heads[i];
                          final edit = _edits[head.id];
                          if (edit == null) return const SizedBox.shrink();
                          return _DisplayCard(
                            head: head,
                            edit: edit,
                            onEditChanged: (newEdit) {
                              setState(() {
                                _dirty = true;
                                _edits[head.id] = newEdit;
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        _buildFooter(theme),
      ],
    );
  }

  Widget _buildFooter(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_applyError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _applyError!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  color: theme.accent,
                ),
              ),
            ),
          SettingsActionButton(
            label: 'Apply Changes',
            onTap: _apply,
            primary: true,
            loading: _applying,
            enabled: _dirty && !_applying,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DisplayDiagram — draggable arrangement view
// ---------------------------------------------------------------------------

const _diagramColors = [
  Color(0xFF4C8BF5),
  Color(0xFF34A853),
  Color(0xFFFBBC04),
  Color(0xFFEA4335),
  Color(0xFF9C27B0),
];

class _DisplayDiagram extends StatefulWidget {
  const _DisplayDiagram({
    required this.heads,
    required this.edits,
    required this.onPositionsChanged,
  });

  final List<ZwlrOutputHeadV1> heads;
  final Map<int, _DisplayEdit> edits;

  /// One call per pointer move while dragging (a single entry), and one on
  /// drop carrying every head the settle moved.
  final void Function(Map<int, ({int x, int y})> positions) onPositionsChanged;

  @override
  _DisplayDiagramState createState() => _DisplayDiagramState();
}

class _DisplayDiagramState extends State<_DisplayDiagram> {
  static const double _height = 260;
  static const double _padding = 16;

  // Accumulated *unsnapped* drag position (in logical pixels) per head id. The
  // reported position is snapped; this one is not, so the rect does not fight
  // the cursor between snap targets and sub-pixel deltas are not lost to
  // rounding.
  final Map<int, Offset> _dragAccum = {};

  // The fit is frozen for the duration of a gesture. Recomputing it per pointer
  // move made the whole view zoom and re-anchor continuously, and made the pan
  // delta non-linear because it is divided by this scale.
  DiagramFit? _frozenFit;
  int? _draggingId;

  DisplayBox? _boxFor(ZwlrOutputHeadV1 head) {
    final edit = widget.edits[head.id];
    // A disabled head has no position; it is neither drawn, fitted nor snapped
    // against. It stays toggleable in the card list below.
    if (edit == null || !edit.enabled) return null;
    final mode = edit.selectedMode ?? head.currentMode;
    final size = logicalSizeOf(
      mode?.width ?? 1920,
      mode?.height ?? 1080,
      edit.scale,
      edit.transform,
    );
    return (
      id: head.id,
      x: edit.positionX,
      y: edit.positionY,
      w: math.max(1, size.width.round()),
      h: math.max(1, size.height.round()),
    );
  }

  List<DisplayBox> _boxes() {
    final boxes = <DisplayBox>[];
    for (final head in widget.heads) {
      final box = _boxFor(head);
      if (box != null) boxes.add(box);
    }
    return boxes;
  }

  void _endDrag(int headId) {
    _dragAccum.remove(headId);
    final settled = rebaseToOrigin(relinkDisconnected(_boxes()));
    widget.onPositionsChanged({
      for (final b in settled) b.id: (x: b.x, y: b.y),
    });
    setState(() {
      _frozenFit = null;
      _draggingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final boxes = _boxes();
    return LayoutBuilder(builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, _height);
      final fit = _frozenFit ?? fitBoxes(boxes, viewport, padding: _padding);

      return Container(
        height: _height,
        color: theme.popupBackground.withValues(alpha: 0.6),
        child: Stack(
          children: [
            for (var i = 0; i < widget.heads.length; i++)
              _buildHeadRect(theme, widget.heads[i], i, boxes, fit),
          ],
        ),
      );
    });
  }

  Widget _buildHeadRect(
    ThemeConfig theme,
    ZwlrOutputHeadV1 head,
    int colorIndex,
    List<DisplayBox> boxes,
    DiagramFit fit,
  ) {
    DisplayBox? box;
    for (final b in boxes) {
      if (b.id == head.id) box = b;
    }
    if (box == null) return const SizedBox.shrink();

    final rect = diagramRect(box, fit);
    final color = _diagramColors[colorIndex % _diagramColors.length];
    final dragging = _draggingId == head.id;
    final moving = box;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        // Opaque, not `deferToChild`: the rect's `margin: all(2)` is inset
        // painting, and the `MouseRegion` inside advertises a grab cursor over
        // it — so the outer 2px of every display was cursored for a drag that
        // could not start there. It closes the 4px gutter between two abutting
        // displays, which means a press exactly on a shared edge resolves to
        // whichever rect is later in `boxes`; that is the rule an *overlapping*
        // pair already followed mid-drag.
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) {
          _dragAccum[head.id] = Offset(
            moving.x.toDouble(),
            moving.y.toDouble(),
          );
          setState(() {
            _frozenFit = fit;
            _draggingId = head.id;
          });
        },
        onPanUpdate: (details) {
          final accum = _dragAccum[head.id];
          if (accum == null) return;
          final next = accum + details.delta / fit.scale;
          _dragAccum[head.id] = next;
          final others = [
            for (final b in boxes)
              if (b.id != head.id) b,
          ];
          final snapped = snapPosition(
            moving: moving,
            others: others,
            desiredX: next.dx.round(),
            desiredY: next.dy.round(),
          );
          widget.onPositionsChanged({
            head.id: (x: snapped.x, y: snapped.y),
          });
        },
        onPanEnd: (_) => _endDrag(head.id),
        onPanCancel: () => _endDrag(head.id),
        child: MouseRegion(
          cursor:
              dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: dragging ? 2.5 : 1.5),
            ),
            child: Center(
              child: Text(
                head.name,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: theme.fontFamily,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DisplayCard — one card per head
// ---------------------------------------------------------------------------

class _DisplayCard extends StatelessWidget {
  const _DisplayCard({
    required this.head,
    required this.edit,
    required this.onEditChanged,
  });

  final ZwlrOutputHeadV1 head;
  final _DisplayEdit edit;
  final ValueChanged<_DisplayEdit> onEditChanged;

  static const _scales = [1.0, 1.25, 1.5, 1.75, 2.0];
  static const _transforms = [
    (0, 'Normal'),
    (1, '90°'),
    (2, '180°'),
    (3, '270°'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return PopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardHeader(theme),
          if (edit.enabled) ...[
            Container(height: 1, color: theme.divider),
            _buildCardBody(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildCardHeader(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  head.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (head.description.isNotEmpty)
                  Text(
                    head.description,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          SettingsToggle(
            value: edit.enabled,
            onChanged: (v) => onEditChanged(edit.copyWith(enabled: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBody(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLabel('Resolution', theme),
          const SizedBox(height: 6),
          SettingsDropdown<ZwlrOutputModeV1>(
            items: [
              for (final mode in head.sortedModes)
                SettingsDropdownItem(
                  value: mode,
                  label: mode.label,
                  detail: mode.preferred ? 'preferred' : null,
                ),
            ],
            selected: edit.selectedMode,
            onSelected: (mode) =>
                onEditChanged(edit.copyWith(selectedMode: mode)),
          ),
          const SizedBox(height: 14),
          _buildLabel('Scale', theme),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _scales.map((s) {
              final sel = (edit.scale - s).abs() < 0.01;
              return SettingsOptionButton(
                label: '$s×',
                selected: sel,
                onTap: () => onEditChanged(edit.copyWith(scale: s)),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _buildLabel('Rotation', theme),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _transforms.map((t) {
              final sel = edit.transform == t.$1;
              return SettingsOptionButton(
                label: t.$2,
                selected: sel,
                onTap: () => onEditChanged(edit.copyWith(transform: t.$1)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Not [SettingsSectionLabel]: same style, but that control upper-cases its
  // text and these labels are title-cased ('Resolution', 'Scale', 'Rotation').
  Widget _buildLabel(String text, ThemeConfig theme) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.5),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}
