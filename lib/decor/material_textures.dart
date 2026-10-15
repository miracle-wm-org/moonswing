/// Where a material's pixels come from: a generated tile, or a picture a theme
/// names — and the paint that lays either one over a surface.
///
/// One store for the process, for the leases rule's reason: one FlutterView per
/// bar per monitor means anything a widget owned would be owned N times. A
/// tile is drawn the first time any surface asks for it and is then the same
/// `ui.Image` for every surface that asks again.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:moonswing/decor/material_tiles.dart';
import 'package:moonswing/theme/surface_material.dart';

/// The generated tiles and the loaded pictures, shared by every surface.
///
/// Notifies when a picture finishes loading (or fails to), which is the only
/// thing about it that ever changes on its own; a tile is made synchronously,
/// on first ask, and never changes after.
class MaterialTextures extends ChangeNotifier {
  MaterialTextures._();

  static final MaterialTextures instance = MaterialTextures._();

  /// The most tiles kept. A tile is keyed on its material, tint and density,
  /// so a colour-picker drag over a tint mints one per frame; the working set
  /// is the handful of materials the active theme names.
  static const int _tileLimit = 12;

  final Map<(SurfaceMaterial, int, int), ui.Image> _tiles = {};

  final Map<String, ui.Image> _pictures = {};
  final Set<String> _loading = {};
  final Map<String, String> _failures = {};

  /// Where relative picture paths resolve from — the themes directory, set by
  /// the shell at start-up so this file need not reach for the store.
  String? baseDirectory;

  /// [material]'s tile in [tint] at [devicePixelRatio], drawn now if this is
  /// the first ask. Null for [SurfaceMaterial.none], and null where no image
  /// can be made at all.
  ui.Image? tile(SurfaceMaterial material, Color tint, double devicePixelRatio) {
    if (!material.paints) return null;
    // Half-step buckets: a fractional scale is drawn a touch sharper rather
    // than once per scale a monitor happens to report.
    final dpr = ((devicePixelRatio.clamp(1.0, 3.0) * 2).ceil()) / 2;
    final opaque = tint.withValues(alpha: 1).toARGB32();
    final key = (material, opaque, (dpr * 2).round());
    final cached = _tiles.remove(key);
    if (cached != null) {
      // Re-inserted, so iteration order is least-recently-used first.
      _tiles[key] = cached;
      return cached;
    }
    final size = materialTileSize(material);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);
    paintMaterialTile(canvas, material, Color(opaque));
    final picture = recorder.endRecording();
    ui.Image image;
    try {
      image = picture.toImageSync(
        (size.width * dpr).round(),
        (size.height * dpr).round(),
      );
    } finally {
      picture.dispose();
    }
    if (_tiles.length >= _tileLimit) {
      // Dropped, not disposed: a painter built a frame ago may still hold it,
      // and a shader made from a disposed image throws. The GC frees it once
      // nothing paints with it.
      _tiles.remove(_tiles.keys.first);
    }
    _tiles[key] = image;
    return image;
  }

  /// The picture at [path] once loaded, or null while it loads and for good
  /// when it will not. Asking starts the load; [addListener] hears it land.
  ui.Image? picture(String path) {
    if (path.isEmpty) return null;
    final resolved = resolvePicturePath(path, baseDirectory);
    final ready = _pictures[resolved];
    if (ready != null) return ready;
    if (_loading.contains(resolved) || _failures.containsKey(resolved)) {
      return null;
    }
    _loading.add(resolved);
    _load(resolved);
    return null;
  }

  /// Why [path] is not being painted, or null when it is (or still might be).
  /// A failure is a visible state: the settings pane shows this under the
  /// field rather than leaving the user to wonder why the bar is plain.
  String? failureFor(String path) =>
      path.isEmpty ? null : _failures[resolvePicturePath(path, baseDirectory)];

  /// Forgets failed loads, so a picture that has since been put in place is
  /// tried again. The retry the failure state offers.
  void retryFailed() {
    if (_failures.isEmpty) return;
    _failures.clear();
    notifyListeners();
  }

  Future<void> _load(String resolved) async {
    try {
      final bytes = await File(resolved).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      _pictures[resolved] = frame.image;
      if (_pictures.length > 8) {
        // Dropped rather than disposed, for the tiles' reason.
        _pictures.remove(_pictures.keys.first);
      }
    } catch (e) {
      _failures[resolved] = e is FileSystemException
          ? 'Cannot read $resolved'
          : 'Not a picture the shell can decode: $resolved';
    } finally {
      _loading.remove(resolved);
    }
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _tiles.clear();
    _pictures.clear();
    _failures.clear();
    _loading.clear();
  }

  @visibleForTesting
  int get tileCount => _tiles.length;
}

/// [path] as a file: `~/…` under `$HOME`, absolute as written, and anything
/// else relative to [base] (the themes directory), so a theme and its
/// pictures can be copied about as one folder.
String resolvePicturePath(String path, String? base) {
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ?? '';
    return '$home${path.substring(1)}';
  }
  if (path.startsWith('/') || base == null || base.isEmpty) return path;
  return base.endsWith('/') ? '$base$path' : '$base/$path';
}

/// The matrix an [ImageShader] needs to lay a tile drawn at [pixelScale]
/// physical pixels per logical one over a surface, with its grain turned a
/// quarter when [across] and its origin at [origin].
///
/// Hand-built rather than a `Matrix4`: it is one rotation, one scale and one
/// translation, column-major as `ImageShader` reads it.
Float64List materialShaderTransform({
  bool across = false,
  double pixelScale = 1.0,
  Offset origin = Offset.zero,
}) {
  final s = 1 / pixelScale;
  final angle = across ? math.pi / 2 : 0.0;
  final a = math.cos(angle) * s;
  final b = math.sin(angle) * s;
  return Float64List.fromList([
    a, b, 0, 0, //
    -b, a, 0, 0, //
    0, 0, 1, 0, //
    origin.dx, origin.dy, 0, 1,
  ]);
}

/// A paint that fills with [image] repeated, at [opacity].
///
/// The paint's colour carries only alpha: a shader's output is modulated by
/// the paint's opacity, which is how a material's tint alpha becomes its
/// strength over the fill beneath it.
Paint materialPaint(
  ui.Image image, {
  required double pixelScale,
  bool across = false,
  Offset origin = Offset.zero,
  double opacity = 1.0,
}) =>
    Paint()
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        materialShaderTransform(
          across: across,
          pixelScale: pixelScale,
          origin: origin,
        ),
        filterQuality: FilterQuality.medium,
      )
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

/// The tile or picture a surface is painted with, and how to scale it: a
/// picture names [path] and wins once it loads; until then — and for good if
/// it will not — the [material] tile in [tint] stands in.
({ui.Image image, double pixelScale})? resolveSurfaceImage({
  required SurfaceMaterial material,
  required Color tint,
  required double devicePixelRatio,
  String path = '',
}) {
  final textures = MaterialTextures.instance;
  final picture = textures.picture(path);
  // A picture's pixels are taken as logical pixels: a 256px photograph of
  // bark covers 256 logical pixels of bar on any monitor.
  if (picture != null) return (image: picture, pixelScale: 1.0);
  final tile = textures.tile(material, tint, devicePixelRatio);
  if (tile == null) return null;
  final dpr = ((devicePixelRatio.clamp(1.0, 3.0) * 2).ceil()) / 2;
  return (image: tile, pixelScale: dpr);
}
