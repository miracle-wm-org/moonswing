// The analog clock desktop widget: the time on a dial, to the minute.
//
// The sixth entry in `DesktopWidgetRegistry`, built the way Tux is — a store
// with a lease, a painter under a repaint boundary, and the theme's own card
// rather than a picture of its own.
//
// Three things a change here has to keep true:
//
// - **There is no second hand.** It is the feature, not an omission: a hand
//   that sweeps seconds is a repaint a second, forever, on a desktop surface
//   with no repaint boundary above it and one FlutterView per monitor behind
//   it. The widget wakes once a minute and is idle in between, which is the
//   deal every store in the shell is written to keep.
// - **Its detail is chosen by pixels, not by span, and chosen by the painter.**
//   The other widgets switch layout on `DesktopWidgetContext.atLeast` because
//   their content is text and a cell is a column of it. This one is a circle
//   taking the card's shorter edge, and whether sixty marks or twelve numerals
//   are legible is a question about pixels — which matters, because
//   `cell_width` is configurable down to 32 and a 4x4 card of those is smaller
//   than a 1x1 of the default ones. It is answered inside `ClockFacePainter`
//   rather than by a `LayoutBuilder`, because a rebuild inside one of those
//   marks it needing layout, and a relayout steps over the repaint boundary
//   nested inside it — so the minute turning over would re-record the desktop's
//   whole surface picture and damage the whole output.
// - **Nothing on the card animates.** No entrance on the minute turning over,
//   for the fortune and lunar cards' reason: it would be the only moving thing
//   on the desktop. The hands are simply somewhere else the next time they are
//   drawn, which is what a clock looks like.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/clock/clock_face.dart';
import 'package:moonswing/clock/clock_hands.dart';
import 'package:moonswing/clock/minute_clock_store.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';

/// The widget's body. Public and store-injectable so a widget test can name the
/// minute it is pretending to be and pump it with no timer behind it.
class AnalogClockWidget extends StatefulWidget {
  AnalogClockWidget({super.key, MinuteClockStore? store})
      : store = store ?? MinuteClockStore.instance;

  final MinuteClockStore store;

  @override
  State<AnalogClockWidget> createState() => _AnalogClockWidgetState();
}

class _AnalogClockWidgetState extends State<AnalogClockWidget> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
  }

  @override
  void didUpdateWidget(AnalogClockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.release();
    widget.store.acquire();
  }

  @override
  void dispose() {
    widget.store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The minute is subscribed to here and nowhere above: `ClockFace` centres a
    // square in whatever rectangle the grid hands over, so a card resized wide
    // and left one row tall is a small clock with room either side of it —
    // which is the honest answer, since an oval would not be a clock. Nothing
    // is measured, so nothing above the face is disturbed when the hands move.
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => ClockFace(hands: ClockHands.at(widget.store.now)),
    );
  }
}

/// The "Add widget…" menu's icon for this type. Named so a test can build a
/// [DesktopWidgetSpec] without picking an unrelated glyph.
const FaIconData analogClockDesktopWidgetIcon = FontAwesomeIcons.clock;

/// The registry entry. Registered from `main()` beside Tux's.
final DesktopWidgetSpec analogClockDesktopWidget = DesktopWidgetSpec(
  type: 'analog_clock',
  name: 'Analog clock',
  description: 'The time on a dial, without the ticking',
  icon: analogClockDesktopWidgetIcon,
  // A dial is a picture, and a picture is what a single cell holds — Tux's
  // floor, for Tux's reason. Two cells square is the default because that is
  // the smallest card whose face carries its minute marks.
  minSpan: (columns: 1, rows: 1),
  // Lower than the picture-backed cards' 6x4 on purpose: the face takes the
  // shorter edge, so past this a wider card is only emptier surface beside the
  // same clock.
  maxSpan: (columns: 4, rows: 4),
  defaultSpan: (columns: 2, rows: 2),
  // Tighter than the default card inset: the face is a circle inside a square
  // box, so it is already inset by the corner it does not fill, and the usual
  // 10 on top of that leaves a small card mostly rim.
  padding: const EdgeInsets.all(6),
  builder: (context, widget) => AnalogClockWidget(),
);
