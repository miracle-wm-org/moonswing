import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/notification_service.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The card's own size — the part the pointer aims at.
///
/// A rectangle rather than the 48px circle this was, because the card now says
/// what arrived. A circle with a number in it tells the user only that
/// *something* did, which on a machine they have walked back to is the question
/// rather than the answer; the width below is what holds an application's name
/// over a one-line summary at the panel's own reading size.
const double kNotificationBadgeWidth = 328;
const double kNotificationBadgeHeight = 76;

/// The corner radius. The card's, not the theme's `popup_radius`: this floats
/// over the wallpaper as its own surface rather than out of a bar, so it takes
/// the shell's card rounding like the notification cards inside the panel.
const double kNotificationBadgeRadius = ShellRadii.card;

/// The square the bell and its count sit in, at the card's leading edge.
const double kNotificationBadgeGlyphBox = 44;

/// The gap between the badge's surface and the edges it is anchored to.
///
/// Deliberately *only* a gap. The badge does not inset itself past the bars: its
/// layer surface keeps gtk-layer-shell's default exclusive zone of 0, which means
/// "move me so I don't occlude surfaces that reserved space" — so the compositor
/// has already placed it clear of the bars, their margins included. Adding
/// `panelInsetsFor` would count every bar twice and hang the badge a bar's height
/// out into the middle of the screen. It is also why the badge must never call
/// `spanFullOutput`: a zone of -1 asks the compositor to stop doing that.
const double kNotificationBadgeGap = 14;

/// Room for the card's shadow, on every side.
///
/// The surface is bigger than the card because a `BoxShadow` paints *outside*
/// its box and this window clips at its edge — `popupShadowInsets`' problem one
/// layer down. Kept as tight as that allows: with no input-region support, every
/// pixel of this surface is a pixel of the output that swallows clicks.
const double kNotificationBadgeShadowInset = 12;

/// How far the card starts to the right of where it settles.
///
/// A short distance on purpose. The surface has to be wide enough to hold the
/// card while it is still outside its resting place — a slide inside a window
/// that clips at the card's own box is the card being wiped on rather than
/// moved in — and this surface is pinned to the corner of every output, where
/// every pixel of it eats clicks.
const double kNotificationBadgeSlide = 28;

/// The padding [NotificationBadge] lays itself out under. The right side
/// carries the slide's room as well as the shadow's.
const EdgeInsets kNotificationBadgeInsets = EdgeInsets.fromLTRB(
  kNotificationBadgeShadowInset,
  kNotificationBadgeShadowInset,
  kNotificationBadgeShadowInset + kNotificationBadgeSlide,
  kNotificationBadgeShadowInset,
);

/// The surface size those imply. Read by the root when it creates the window
/// and by [NotificationBadge] when it lays itself out inside it, so the card
/// lands where the margins say it does.
const Size kNotificationBadgeWindowSize = Size(
  kNotificationBadgeWidth +
      2 * kNotificationBadgeShadowInset +
      kNotificationBadgeSlide,
  kNotificationBadgeHeight + 2 * kNotificationBadgeShadowInset,
);

/// How long the card takes to arrive.
const Duration kNotificationBadgeEnter = Duration(milliseconds: 420);

/// How long the card takes to leave once the pointer has passed over it.
///
/// Quicker than the arrival: the user has already seen it, and a card that
/// lingers after being waved away is one still asking for attention.
const Duration kNotificationBadgeExit = Duration(milliseconds: 260);

/// How long one bounce lasts.
const Duration kNotificationBadgeBump = Duration(milliseconds: 380);

/// How far the bounce lifts the card at its highest.
const double kNotificationBadgeBounce = 9;

/// The number the bubble shows for [count] — three characters at the most, so
/// a machine that has been left alone all weekend does not widen the surface
/// the badge was sized for.
String notificationBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// The floating "you have notifications" card.
///
/// One per monitor, in a small root-owned overlay window that exists only while
/// something is unread — the OSD's rule and its reason: a permanently mapped
/// surface would sit in the corner of every output eating clicks.
///
/// Four things a change here has to keep true:
///
/// - **It is the same count the bell shows, from the same store, and it opens the
///   same panel.** The badge exists because the bell may not: a user with no
///   `notifications` module in any panel would otherwise have a shell that
///   silently swallows every notification. It is not a second inbox, and what it
///   shows of the message is a *trailer* — one line of the newest one — not the
///   message, which is what the panel this opens is for.
/// - **It arrives by sliding in, and bounces when something lands in it.** The
///   entrance is a slide out of the edge it is anchored to with a bounce on the
///   end of it, and every further arrival replays that bounce, so a card the
///   user has already been shown still moves when a second notification reaches
///   it.
/// - **Nothing animates at rest.** The entrance plays once and a bounce plays on
///   an arrival; both settle. There is deliberately no idle bounce on a timer:
///   this surface can be on screen for hours, it has no repaint boundary of its
///   own in the window it lives in, and a shell that animates while nobody has
///   asked it anything is the thing `CLAUDE.md`'s repaint discipline exists to
///   prevent. The card's *presence* is the standing signal; motion is reserved
///   for the moment something changes.
/// - **The card is the whole box.** [HoverRegion] emits the opaque detector, so
///   the rectangle is the hover box and the tap box alike. A tap opens the
///   panel; a pointer that crosses the card and leaves *without* tapping is the
///   user waving it away, so the card slides back out and asks the store to
///   keep it down ([NotificationStore.hideBadge]) — nothing is read or
///   removed, the bell keeps its count, and the next arrival brings it back.
///   There is no X: the pointer's passing is the dismissal, and a close button
///   the size of a glyph was a target the pointer had to be aimed at.
class NotificationBadge extends StatefulWidget {
  const NotificationBadge({super.key, required this.onTap});

  /// Asks for the notification panel. The root supplies this rather than the
  /// badge poking [NotificationPanelController] itself, because the root knows
  /// which monitor this badge is on and can open the panel on that one.
  final VoidCallback onTap;

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

/// One bounce, as a vertical offset: down, back past rest, and a smaller
/// rebound.
///
/// The card is anchored to the *top* of the output, so it bounces downward off
/// that edge rather than up off a floor that is not there.
///
/// An [Animatable] rather than an [Animation], so the entrance and the bump are
/// the same bounce driven by two controllers — an arrival cannot land in a
/// bounce that differs from the one the card came in on.
final Animatable<double> _bounce = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(begin: 0.0, end: kNotificationBadgeBounce)
        .chain(CurveTween(curve: Curves.easeOut)),
    weight: 30,
  ),
  TweenSequenceItem(
    tween: Tween(begin: kNotificationBadgeBounce, end: 0.0)
        .chain(CurveTween(curve: Curves.easeIn)),
    weight: 30,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 0.0, end: kNotificationBadgeBounce * 0.38)
        .chain(CurveTween(curve: Curves.easeOut)),
    weight: 20,
  ),
  TweenSequenceItem(
    tween: Tween(begin: kNotificationBadgeBounce * 0.38, end: 0.0)
        .chain(CurveTween(curve: Curves.easeIn)),
    weight: 20,
  ),
]);

class _NotificationBadgeState extends State<NotificationBadge>
    with TickerProviderStateMixin {
  /// The arrival: the slide, and the bounce it lands on.
  late final AnimationController _enterController;
  late final Animation<double> _slide;
  late final Animation<double> _enterBounce;
  late final Animation<double> _fade;

  /// The bounce on its own, replayed by every further notification.
  late final AnimationController _bumpController;
  late final Animation<double> _bump;

  /// The departure: the slide back out toward the edge, and the fade.
  late final AnimationController _exitController;

  /// Whether the pointer is over the card now, and whether it has tapped the
  /// card since it arrived. Plain fields: neither is painted.
  bool _pointerInside = false;
  bool _tapped = false;

  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: kNotificationBadgeEnter,
    );
    // Two thirds slide, one third bounce, off one controller: the bounce is
    // what the slide lands *in*, not a second animation that happens after it,
    // so the card cannot be seen to stop and then start again.
    _slide = Tween<double>(begin: kNotificationBadgeSlide, end: 0.0).animate(
      CurvedAnimation(
        parent: _enterController,
        curve: const Interval(0.0, 0.62, curve: Curves.easeOutCubic),
      ),
    );
    _enterBounce = _bounce.animate(
      CurvedAnimation(
        parent: _enterController,
        curve: const Interval(0.55, 1.0),
      ),
    );
    // Quick, and over well before the slide is: the card has to be solid by the
    // time it is over the wallpaper it is being read against.
    _fade = CurvedAnimation(
      parent: _enterController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _bumpController = AnimationController(
      vsync: this,
      duration: kNotificationBadgeBump,
    );
    _bump = _bounce.animate(_bumpController);

    _exitController = AnimationController(
      vsync: this,
      duration: kNotificationBadgeExit,
    );

    _prevCount = NotificationStore.instance.unreadCount;
    NotificationStore.instance.addListener(_onStoreChanged);
    _enterController.forward();
  }

  @override
  void dispose() {
    NotificationStore.instance.removeListener(_onStoreChanged);
    _enterController.dispose();
    _bumpController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    final count = NotificationStore.instance.unreadCount;
    // Only *more* notifications bounce it. A dismissal moving the number down
    // is the user tidying up, and re-animating for that would draw the eye back
    // to the thing they are in the middle of clearing. The entrance carries its
    // own bounce, so an arrival that lands while the card is still coming in is
    // left alone rather than bounced twice.
    if (count > _prevCount) {
      // Something new arriving while the card is on its way out brings it back:
      // it was waved away over the old messages, not this one. Setting the
      // value cancels the departure, so its `hideBadge` never runs.
      if (_exitController.value > 0) _exitController.value = 0;
      if (_enterController.isCompleted) _bumpController.forward(from: 0.0);
    }
    _prevCount = count;
    if (mounted) setState(() {});
  }

  void _onEnter() {
    _pointerInside = true;
    _tapped = false;
  }

  /// The pointer left the card. Without a tap in between, that is the user
  /// having seen it and moved on, so the card leaves.
  ///
  /// Only an exit that follows an [_onEnter] counts: `MouseRegion` also reports
  /// content moving under a stationary cursor, and the card sliding in under a
  /// pointer parked in the corner is not the user waving it away.
  void _onExit() {
    if (!_pointerInside) return;
    _pointerInside = false;
    if (_tapped || _exitController.isAnimating) return;
    _exitController.forward().then((_) {
      if (mounted) NotificationStore.instance.hideBadge();
    });
  }

  void _onTapDown() {
    _tapped = true;
    // A tap during the departure takes the card back: the user has changed
    // their mind about it, and the panel it opens takes it down anyway.
    if (_exitController.value > 0) _exitController.value = 0;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = NotificationStore.instance;
    final unread = store.unreadCount;
    final newest = _newestUnread(store);

    // Built here rather than inside the hover builder, the repaint rules'
    // "hand unchanged children in": this is three paragraphs, and a pointer
    // crossing the card must move a decoration rather than re-shape them.
    final content = _BadgeContent(
      theme: theme,
      count: unread,
      newest: newest,
    );

    // The exit is the entrance's slide run the other way, fading as it goes,
    // so the card leaves by the edge it came in from.
    final exit = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeInCubic,
    );

    return Padding(
      padding: kNotificationBadgeInsets,
      child: FadeTransition(
        opacity: _fade,
        child: FadeTransition(
          opacity: ReverseAnimation(exit),
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _enterController,
              _bumpController,
              _exitController,
            ]),
            // Built outside the builder: the card measures two paragraphs, and
            // re-shaping them on every frame of a bounce is exactly what the
            // repaint rules say to hand in unchanged instead.
            child: HoverRegion(
              onEnter: _onEnter,
              onExit: _onExit,
              // Tap-down, not tap: `PopupDismissArea`'s ancestor `Listener`
              // fires before any descendant recognizer, so every popup
              // toggle in the shell opens on the down edge and is guarded
              // there.
              onTapDown: (_) => _onTapDown(),
              builder: (context, hovered) =>
                  _BadgeCard(theme: theme, hovered: hovered, child: content),
            ),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                _slide.value + exit.value * kNotificationBadgeSlide,
                _enterBounce.value + _bump.value,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// The message the card reports: the most recently arrived unread one.
  ///
  /// The store keeps its list newest-first, so this is the first unread entry
  /// on it. Null only in the frame between the last one being read or dismissed
  /// and the root taking this window down.
  static NotificationItem? _newestUnread(NotificationStore store) {
    for (final item in store.items) {
      if (!item.read) return item;
    }
    return null;
  }
}

/// The card's box: the only part of it a hover moves.
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.theme,
    required this.hovered,
    required this.child,
  });

  final ThemeConfig theme;
  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Opaque whatever the theme says, the settings panel's rule at a much
    // smaller size and for the same reason: this floats over the wallpaper
    // rather than over a surface of the shell's own, and a translucent fill
    // puts whatever photograph the user chose behind two lines of prose.
    final base = theme.popupBackground.withValues(alpha: 1.0);

    // A hover *tints* that surface; it never replaces it. `surface_hover` is
    // sized for a control the width of a word — in the shipped palette it is
    // the accent itself, and in glassy it is a white the card would become
    // once forced opaque — so taking it to full strength under three lines of
    // prose is the wash the repaint-and-palette rules keep off body text: the
    // summary, and the badge-coloured application name above it, both end up
    // on the loudest colour in the theme. 0.16 is the alpha every other
    // hovered row in this panel and in the bar already uses; it is blended
    // into `base` rather than layered over it because this surface has to
    // stay opaque over the wallpaper.
    final fill = hovered
        ? Color.alphaBlend(theme.surfaceHover.atMostAlpha(0.16), base)
        : base;

    return Container(
      width: kNotificationBadgeWidth,
      height: kNotificationBadgeHeight,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(kNotificationBadgeRadius),
        // The badge colour on the rim, not the accent: this is the one surface
        // in the shell whose whole job is to be noticed from across a room, and
        // the accent is already what every hovered button in the bar wears.
        border: Border.all(
          color: theme.notificationBadge.withValues(alpha: hovered ? 1.0 : 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.38),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Any run of whitespace, so a body's own line breaks do not survive into the
/// single line the card has room for. A constant: it is read on every build.
final RegExp _whitespace = RegExp(r'\s+');

/// What the card says: the bell and its count, then what arrived.
class _BadgeContent extends StatelessWidget {
  const _BadgeContent({
    required this.theme,
    required this.count,
    required this.newest,
  });

  final ThemeConfig theme;
  final int count;
  final NotificationItem? newest;

  @override
  Widget build(BuildContext context) {
    final item = newest;
    final extra = count - 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _BadgeGlyph(theme: theme, count: count),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.appName ?? 'Notifications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.bold,
                    color: theme.notificationBadge,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item?.summary ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.label,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // The body when there is one, and how much else is waiting
                  // when there is more. Never both: this is one line, and the
                  // count is the thing a user cannot get anywhere else without
                  // opening the panel.
                  extra > 0
                      ? (extra == 1
                          ? '1 more notification'
                          : '$extra more notifications')
                      : _trailer(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    height: 1.2,
                    color: theme.popupForeground.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
        ),
      ],
    );
  }

  /// One line of the message's body, with its own newlines flattened.
  ///
  /// A body is free text from any application on the machine and routinely
  /// arrives as a paragraph; `maxLines: 1` would otherwise show its first line
  /// only, which for a message that opens with a blank one is nothing at all.
  static String _trailer(NotificationItem? item) {
    final body = item?.body ?? '';
    if (body.isEmpty) return 'Click to open the notification panel';
    return body.replaceAll(_whitespace, ' ').trim();
  }
}

/// The bell, in the badge colour, with the unread count over its shoulder.
///
/// A filled square rather than the bare glyph the circular badge had: at this
/// card's size the glyph alone was the only thing carrying the colour, and the
/// point of the colour is to be seen before anything on the card is read.
class _BadgeGlyph extends StatelessWidget {
  const _BadgeGlyph({required this.theme, required this.count});

  final ThemeConfig theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: kNotificationBadgeGlyphBox,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: kNotificationBadgeGlyphBox,
            height: kNotificationBadgeGlyphBox,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.notificationBadge,
              borderRadius: BorderRadius.circular(ShellRadii.control),
            ),
            child: FaIcon(
              FontAwesomeIcons.bell,
              size: 19,
              color: theme.notificationBadgeForeground,
            ),
          ),
          if (count > 1)
            Positioned(
              top: -6,
              right: -8,
              child: _BadgeCount(theme: theme, count: count),
            ),
        ],
      ),
    );
  }
}

/// The count bubble, drawn over the glyph's corner.
///
/// Ringed in the card's own fill so it reads as punched out of the block rather
/// than as a blob resting on top — `_BrokenDot`'s trick on the bell, which is
/// what keeps a small filled shape legible over any theme. It appears only past
/// one: with a single notification the card already says what it is, and a "1"
/// beside it is a number nobody needed.
class _BadgeCount extends StatelessWidget {
  const _BadgeCount({required this.theme, required this.count});

  final ThemeConfig theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.popupBackground.withValues(alpha: 1.0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.notificationBadge, width: 1.5),
      ),
      child: Text(
        notificationBadgeLabel(count),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: ShellFontSizes.caption,
          height: 1.0,
          fontWeight: FontWeight.bold,
          color: theme.notificationBadge,
        ),
      ),
    );
  }
}
