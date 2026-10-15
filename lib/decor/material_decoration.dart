/// A popup card made of something: a material under its content and a
/// material for its rim.
///
/// [MaterialCardDecoration] wraps the decoration `popupDecoration` would have
/// built — fill, corners, shadow, the attached join's flare — with its rim
/// taken out, and paints three things over it: the card's material (faint, it
/// is read), its rim in a material of its own (bark around heartwood is a
/// trunk), and the rounding that makes that rim a cylinder rather than a
/// frame. Everything the plain card does — `padding` for the rim, the clip
/// path children are cut to, the hit test — answers exactly as the plain card
/// would, so no call site can tell it is not one.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:moonswing/decor/material_textures.dart';
import 'package:moonswing/popup_surface.dart' show AttachedPopupBorder;
import 'package:moonswing/theme/theme_config.dart';

/// [base] — a rimless card — with [theme]'s card material and rim material
/// laid over it.
class MaterialCardDecoration extends Decoration {
  const MaterialCardDecoration({
    required this.base,
    required this.theme,
    required this.rim,
    this.attach,
  });

  /// The card as `popupDecoration` builds it, without its rim.
  final Decoration base;

  /// The theme whose `popup_texture*`, `popup_border_texture*` and
  /// `popup_image` this paints.
  final ThemeConfig theme;

  /// How thick the rim is on each side — the joined side of an attached card
  /// takes none, as its flat rim would.
  final EdgeInsets rim;

  /// The panel edge an attached card is joined to, or null for one that floats.
  /// Decides which way the trunk runs, and so which way its bark does.
  final String? attach;

  /// Whether the trunk runs across the screen (from a side bar) rather than
  /// down it.
  bool get _trunkAcross => attach == 'left' || attach == 'right';

  @override
  EdgeInsetsGeometry get padding => rim;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      base.getClipPath(rect, textDirection);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      base.hitTest(size, position, textDirection: textDirection);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _MaterialCardPainter(
          this, base.createBoxPainter(onChanged ?? () {}), onChanged);

  /// The inside edge of the rim.
  Path innerPath(Rect rect, TextDirection textDirection) {
    final b = base;
    if (b is ShapeDecoration) {
      final shape = b.shape;
      if (shape is AttachedPopupBorder) {
        // The base carries no rim, so its own inner path is its outer one;
        // the same join with the rim's width is what the rim leaves inside.
        return AttachedPopupBorder(
          edge: shape.edge,
          radius: shape.radius,
          attachRadius: shape.attachRadius,
          side: BorderSide(width: theme.popupBorderWidth),
        ).getInnerPath(rect, textDirection: textDirection);
      }
      return shape.getInnerPath(rect, textDirection: textDirection);
    }
    final inner = rim.deflateRect(rect);
    if (b is BoxDecoration && b.borderRadius != null) {
      final r = b.borderRadius!.resolve(textDirection);
      Radius less(Radius c, double dx, double dy) => Radius.elliptical(
          (c.x - dx).clamp(0.0, double.infinity),
          (c.y - dy).clamp(0.0, double.infinity));
      return Path()
        ..addRRect(RRect.fromRectAndCorners(
          inner,
          topLeft: less(r.topLeft, rim.left, rim.top),
          topRight: less(r.topRight, rim.right, rim.top),
          bottomLeft: less(r.bottomLeft, rim.left, rim.bottom),
          bottomRight: less(r.bottomRight, rim.right, rim.bottom),
        ));
    }
    return Path()..addRect(inner);
  }

  @override
  bool operator ==(Object other) =>
      other is MaterialCardDecoration &&
      other.base == base &&
      other.theme == theme &&
      other.rim == rim &&
      other.attach == attach;

  @override
  int get hashCode => Object.hash(base, theme, rim, attach);
}

class _MaterialCardPainter extends BoxPainter {
  _MaterialCardPainter(this.decoration, this.base, VoidCallback? onChanged)
      : super(onChanged);

  final MaterialCardDecoration decoration;
  final BoxPainter base;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    // Shadow and fill, exactly as the plain card.
    base.paint(canvas, offset, configuration);
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final d = decoration;
    final theme = d.theme;
    final dpr = configuration.devicePixelRatio ?? 1.0;
    final dir = configuration.textDirection ?? TextDirection.ltr;
    final rect = offset & size;
    final outer = d.base.getClipPath(rect, dir);

    // The card's own material, under the content.
    final card = resolveSurfaceImage(
      material: theme.popupTexture,
      tint: theme.popupTextureColor,
      devicePixelRatio: dpr,
      path: theme.popupImage,
    );
    if (card != null) {
      canvas.save();
      canvas.clipPath(outer);
      canvas.drawRect(
        outer.getBounds(),
        materialPaint(card.image,
            pixelScale: card.pixelScale,
            across: !d._trunkAcross,
            origin: rect.topLeft,
            opacity: theme.popupTextureColor.a),
      );
      canvas.restore();
    }

    if (d.rim == EdgeInsets.zero) return;
    final inner = d.innerPath(rect, dir);
    final band = Path.combine(PathOperation.difference, outer, inner);
    final bark = resolveSurfaceImage(
      material: theme.popupBorderTexture,
      tint: theme.popupBorderTextureColor,
      devicePixelRatio: dpr,
    );
    canvas.save();
    canvas.clipPath(band);
    final bounds = outer.getBounds();
    canvas.drawRect(
      bounds,
      bark == null
          ? (Paint()..color = theme.popupBorder)
          : materialPaint(bark.image,
              // At half size: a rim is a few pixels deep, and a full-size
              // plate would fill it with one smooth ridge.
              pixelScale: bark.pixelScale * 2,
              // Bark runs along the trunk, and the trunk runs out of the bar.
              across: !d._trunkAcross,
              origin: rect.topLeft,
              opacity: theme.popupBorderTextureColor.a),
    );
    // A trunk is round: lit on one flank, in shade on the other, so the rim
    // reads as the outside of a cylinder rather than a picture frame.
    final (from, to) = d._trunkAcross
        ? (bounds.topCenter, bounds.bottomCenter)
        : (bounds.centerLeft, bounds.centerRight);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          from,
          to,
          const [
            Color(0x38FFF2DC),
            Color(0x00FFF2DC),
            Color(0x00000000),
            Color(0x66000000),
          ],
          const [0.0, 0.3, 0.62, 1.0],
        ),
    );
    canvas.restore();

    // Where the bark meets the heartwood: a dark cut, and the shade it casts
    // a few pixels in over the card.
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.restore();
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xB3000000),
    );
  }

  @override
  void dispose() {
    base.dispose();
    super.dispose();
  }
}
