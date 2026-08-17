// ignore_for_file: library_private_types_in_public_api

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
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
  Map<int, _DisplayEdit> _edits = {};
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

  void _initEditsIfNeeded() {
    final manager = _manager;
    if (manager == null) return;
    for (final head in manager.heads) {
      _edits.putIfAbsent(head.id, () => _DisplayEdit.fromHead(head));
    }
  }

  bool get _hasChanges {
    final manager = _manager;
    if (manager == null) return false;
    for (final head in manager.heads) {
      final edit = _edits[head.id];
      if (edit == null) continue;
      if (edit.enabled != head.enabled) return true;
      if (edit.positionX != head.positionX) return true;
      if (edit.positionY != head.positionY) return true;
      if (edit.enabled) {
        if (edit.selectedMode?.id != head.currentMode?.id) return true;
        if ((edit.scale - head.scale).abs() > 0.01) return true;
        if (edit.transform != head.transform) return true;
      }
    }
    return false;
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
        setState(() {
          _applying = false;
          _edits = {};
        });
        _reload();
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

  Future<void> _reload() async {
    await _waylandClient?.close();
    _waylandClient = null;
    _manager = null;
    if (mounted) {
      setState(() {
        _loaded = false;
        _edits = {};
      });
    }
    _connect();
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
    _initEditsIfNeeded();
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
                  theme: theme,
                  onPositionChanged: (headId, x, y) {
                    setState(() {
                      final edit = _edits[headId];
                      if (edit != null) {
                        _edits[headId] =
                            edit.copyWith(positionX: x, positionY: y);
                      }
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
                            theme: theme,
                            onEditChanged: (newEdit) {
                              setState(() => _edits[head.id] = newEdit);
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
          _ActionButton(
            label: 'Apply Changes',
            onTap: _apply,
            primary: true,
            loading: _applying,
            enabled: _hasChanges && !_applying,
            theme: theme,
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
    required this.theme,
    required this.onPositionChanged,
  });

  final List<ZwlrOutputHeadV1> heads;
  final Map<int, _DisplayEdit> edits;
  final ThemeConfig theme;
  final void Function(int headId, int x, int y) onPositionChanged;

  @override
  _DisplayDiagramState createState() => _DisplayDiagramState();
}

class _DisplayDiagramState extends State<_DisplayDiagram> {
  // Accumulated fractional drag offset (in display pixels) per head id.
  final Map<int, Offset> _dragAccum = {};

  int _headPxW(ZwlrOutputHeadV1 head, _DisplayEdit edit) =>
      (edit.selectedMode ?? head.currentMode)?.width ?? 1920;

  int _headPxH(ZwlrOutputHeadV1 head, _DisplayEdit edit) =>
      (edit.selectedMode ?? head.currentMode)?.height ?? 1080;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const padding = 12.0;
      const height = 148.0;
      final w = constraints.maxWidth;

      // Compute bounding box in display-pixel space.
      int minX = 0, minY = 0, maxX = 1, maxY = 1;
      bool first = true;
      for (final head in widget.heads) {
        final edit = widget.edits[head.id];
        if (edit == null) continue;
        final pw = _headPxW(head, edit);
        final ph = _headPxH(head, edit);
        if (first) {
          minX = edit.positionX;
          minY = edit.positionY;
          maxX = edit.positionX + pw;
          maxY = edit.positionY + ph;
          first = false;
        } else {
          minX = math.min(minX, edit.positionX);
          minY = math.min(minY, edit.positionY);
          maxX = math.max(maxX, edit.positionX + pw);
          maxY = math.max(maxY, edit.positionY + ph);
        }
      }

      final totalW = (maxX - minX).toDouble();
      final totalH = (maxY - minY).toDouble();
      final scaleX = (w - padding * 2) / totalW;
      final scaleY = (height - padding * 2) / totalH;
      final scale = math.min(scaleX, scaleY).clamp(0.00001, double.infinity);

      return Container(
        height: height,
        color: widget.theme.popupBackground.withValues(alpha: 0.6),
        child: Stack(
          children: [
            for (var i = 0; i < widget.heads.length; i++)
              _buildHeadRect(
                widget.heads[i],
                i,
                scale,
                minX,
                minY,
                padding,
              ),
          ],
        ),
      );
    });
  }

  Widget _buildHeadRect(
    ZwlrOutputHeadV1 head,
    int colorIndex,
    double scale,
    int minX,
    int minY,
    double padding,
  ) {
    final edit = widget.edits[head.id];
    if (edit == null) return const SizedBox.shrink();

    final pw = _headPxW(head, edit);
    final ph = _headPxH(head, edit);
    final diagX = padding + (edit.positionX - minX) * scale;
    final diagY = padding + (edit.positionY - minY) * scale;
    final diagW = pw * scale;
    final diagH = ph * scale;
    final color = _diagramColors[colorIndex % _diagramColors.length];
    final disabled = !edit.enabled;

    return Positioned(
      left: diagX,
      top: diagY,
      width: diagW,
      height: diagH,
      child: GestureDetector(
        onPanStart: (_) {
          _dragAccum[head.id] = Offset(
            edit.positionX.toDouble(),
            edit.positionY.toDouble(),
          );
        },
        onPanUpdate: (details) {
          final accum = _dragAccum[head.id];
          if (accum == null) return;
          final newAccum = accum + details.delta / scale;
          _dragAccum[head.id] = newAccum;
          widget.onPositionChanged(
            head.id,
            newAccum.dx.round(),
            newAccum.dy.round(),
          );
        },
        onPanEnd: (_) => _dragAccum.remove(head.id),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Opacity(
            opacity: disabled ? 0.35 : 1.0,
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: Text(
                  head.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: widget.theme.fontFamily,
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
    required this.theme,
    required this.onEditChanged,
  });

  final ZwlrOutputHeadV1 head;
  final _DisplayEdit edit;
  final ThemeConfig theme;
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
    return Container(
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardHeader(),
          if (edit.enabled) ...[
            Container(height: 1, color: theme.divider),
            _buildCardBody(),
          ],
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
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
          _EnableToggle(
            enabled: edit.enabled,
            theme: theme,
            onTap: () => onEditChanged(edit.copyWith(enabled: !edit.enabled)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLabel('Resolution'),
          const SizedBox(height: 6),
          _ModeDropdown(
            modes: head.sortedModes,
            selectedMode: edit.selectedMode,
            theme: theme,
            onModeSelected: (mode) =>
                onEditChanged(edit.copyWith(selectedMode: mode)),
          ),
          const SizedBox(height: 14),
          _buildLabel('Scale'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _scales.map((s) {
              final sel = (edit.scale - s).abs() < 0.01;
              return _OptionButton(
                label: '$s×',
                selected: sel,
                theme: theme,
                onTap: () => onEditChanged(edit.copyWith(scale: s)),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _buildLabel('Rotation'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _transforms.map((t) {
              final sel = edit.transform == t.$1;
              return _OptionButton(
                label: t.$2,
                selected: sel,
                theme: theme,
                onTap: () => onEditChanged(edit.copyWith(transform: t.$1)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
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

// ---------------------------------------------------------------------------
// _EnableToggle
// ---------------------------------------------------------------------------

class _EnableToggle extends StatefulWidget {
  const _EnableToggle({
    required this.enabled,
    required this.theme,
    required this.onTap,
  });

  final bool enabled;
  final ThemeConfig theme;
  final VoidCallback onTap;

  @override
  _EnableToggleState createState() => _EnableToggleState();
}

class _EnableToggleState extends State<_EnableToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final color = widget.enabled ? theme.accent : theme.divider;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered ? color.withValues(alpha: 0.8) : color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                left: widget.enabled ? 22 : 2,
                top: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ModeDropdown — inline expanding mode selector
// ---------------------------------------------------------------------------

class _ModeDropdown extends StatefulWidget {
  const _ModeDropdown({
    required this.modes,
    required this.selectedMode,
    required this.theme,
    required this.onModeSelected,
  });

  final List<ZwlrOutputModeV1> modes;
  final ZwlrOutputModeV1? selectedMode;
  final ThemeConfig theme;
  final ValueChanged<ZwlrOutputModeV1> onModeSelected;

  @override
  _ModeDropdownState createState() => _ModeDropdownState();
}

class _ModeDropdownState extends State<_ModeDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final current = widget.selectedMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DropdownTrigger(
          label: current?.label ?? '—',
          open: _open,
          theme: theme,
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: theme.controlSurface,
              border: Border.all(color: theme.divider),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.modes.length,
              itemBuilder: (_, i) {
                final mode = widget.modes[i];
                final sel = mode.id == widget.selectedMode?.id;
                return _ModeListItem(
                  mode: mode,
                  selected: sel,
                  theme: theme,
                  onTap: () {
                    widget.onModeSelected(mode);
                    setState(() => _open = false);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DropdownTrigger extends StatefulWidget {
  const _DropdownTrigger({
    required this.label,
    required this.open,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool open;
  final ThemeConfig theme;
  final VoidCallback onTap;

  @override
  _DropdownTriggerState createState() => _DropdownTriggerState();
}

class _DropdownTriggerState extends State<_DropdownTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final bg =
        _hovered ? theme.surfaceHover : theme.controlSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              FaIcon(
                widget.open
                    ? FontAwesomeIcons.chevronUp
                    : FontAwesomeIcons.chevronDown,
                size: 10,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeListItem extends StatefulWidget {
  const _ModeListItem({
    required this.mode,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final ZwlrOutputModeV1 mode;
  final bool selected;
  final ThemeConfig theme;
  final VoidCallback onTap;

  @override
  _ModeListItemState createState() => _ModeListItemState();
}

class _ModeListItemState extends State<_ModeListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final bg = widget.selected
        ? theme.accent.withValues(alpha: 0.15)
        : _hovered
            ? theme.surfaceHover
            : const Color(0x00000000);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: bg,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color:
                        widget.selected ? theme.accent : theme.popupForeground,
                  ),
                ),
              ),
              if (widget.mode.preferred)
                Text(
                  'preferred',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OptionButton — pill toggle for scale / transform
// ---------------------------------------------------------------------------

class _OptionButton extends StatefulWidget {
  const _OptionButton({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ThemeConfig theme;
  final VoidCallback onTap;

  @override
  _OptionButtonState createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final Color bg;
    if (widget.selected) {
      bg = theme.accent;
    } else if (_hovered) {
      bg = theme.surfaceHover;
    } else {
      bg = theme.controlSurface;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected ? theme.accent : theme.divider,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: widget.selected
                  ? const Color(0xFFFFFFFF)
                  : theme.popupForeground,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ActionButton — reuse pattern from network.dart
// ---------------------------------------------------------------------------

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.theme,
    this.primary = false,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final ThemeConfig theme;
  final bool primary;
  final bool loading;
  final bool enabled;

  @override
  _ActionButtonState createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final canTap = widget.enabled && !widget.loading;
    final Color bg;
    if (widget.primary) {
      bg = _hovered && canTap
          ? theme.accent.withValues(alpha: 0.85)
          : canTap
              ? theme.accent
              : theme.accent.withValues(alpha: 0.4);
    } else {
      bg = _hovered && canTap ? theme.surfaceHover : theme.divider;
    }

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canTap ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: widget.loading
                ? const LoadingIndicator(size: 14)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color: widget.primary
                          ? const Color(0xFFFFFFFF)
                          : theme.popupForeground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
