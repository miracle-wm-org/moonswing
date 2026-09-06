/// The themes that ship with the shell.
///
/// Embedded here rather than installed to a share directory because nothing in
/// the shell resolves paths relative to the bundle — the wallpapers the Makefile
/// *does* install are found only via a hardcoded `$HOME/.local/share`, which
/// breaks under a custom `PREFIX`. Seeding from a constant works identically in
/// `flutter run`, `make install` and the snap.
///
/// `ThemeStore` rewrites any entry whose file differs at start-up and treats
/// membership in [kBuiltInThemes] as the read-only test, so this map is the
/// single source of truth for "shipped".
library;

/// Slug -> the full TOML text of that theme file.
///
/// Every key a theme understands is spelled out in every entry: a shipped
/// theme must never inherit a [ThemeConfig] default, or changing a default
/// would silently restyle it.
const Map<String, String> kBuiltInThemes = {
  'graceful': _graceful,
  'forest': _forest,
  'dracula': _dracula,
  'glassy': _glassy,
  'midnight': _midnight,
  'carbon': _carbon,
};

const String _graceful = '''
# Graceful — the shell's own palette: deep maroon over near-black.
name = "Graceful"

font = "Ubuntu Sans"
font_size = 13.0

accent               = "#853953"
foreground           = "#F3F4F4"
surface_hover        = "#853953"
surface_pressed      = "#612D53"
workspace_background = "#2C2C2C"
popup_background     = "#2C2C2C"
popup_foreground     = "#F3F4F4"
control_surface      = "#39393D"
slider_track         = "#612D53"
muted                = "#853953"
divider              = "#33F3F4F4"
scrim                = "#882C2C2C"

# The bar: a maroon-to-black fade at 93% opacity, which is what the shell has
# always drawn. panel_background's alpha sets the opacity of every stop.
panel_background     = "#EE2C2C2C"
panel_gradient       = true

# Flush to the screen edge, square, no rim — the geometry the bar has always
# had. panel_border is spelled out even though nothing draws it at width 0: it
# is the colour a rim would take if one were switched on.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33F3F4F4"
panel_border_width   = 0.0

# Popups: rounded cards with a hairline rim, which is the shape the shell's
# menus have always drawn — now stated once instead of hardcoded at fifteen
# call sites. Unlike the bar a popup rounds all four corners: nothing sits
# behind it to cut a wedge out of. The rim colour is `divider`, which is what
# those menus used.
popup_radius         = 8.0
popup_border         = "#33F3F4F4"
popup_border_width   = 1.0

# A bar popup sits flush against the bar and grows out of it: no gap, and a
# square butt join, so the menu's sides continue the panel's. The join drops its
# rim and its shadow, so nothing draws a seam across it. popup_attach_radius
# above zero would flare the join outward into the bar instead — a concave
# fillet, not a rounded corner — which suits a softer theme than this one.
popup_gap            = 0.0
popup_attach_radius  = 0.0

# The card's lift. Blur is the reach past the edge and the offset pushes it
# downward, exactly as a CSS box-shadow reads; a popup grows its own window by
# that reach so the shadow is not clipped at the surface edge, and is
# repositioned by the same amount so the card stays put. An alpha of 0 here is
# the off switch.
popup_shadow_color   = "#66000000"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0

# How a popup arrives, and — reversed — how it leaves. The card is attached to
# the bar here, so it slides the short distance out of it and back in again.
popup_animation      = "slide"
''';

const String _forest = '''
# Forest — pine and moss over a near-black green, with a lit rim.
#
# The palette is one hue held throughout: every surface is a green so dark it
# reads as black until something is laid beside it, and the only saturated
# green in the theme is the accent. That is what keeps a single-hue theme from
# looking tinted — the colour is spent where it means something (the active
# workspace, a pressed control, the bright end of the bar) and withheld
# everywhere else.
#
# It is a *floating* theme, like glassy, but for the opposite reason: glassy
# needs a rim because a translucent bar has no edge of its own, while this one
# is nearly opaque and wants the rim as the one lit line in the picture. The
# bar and the popups therefore carry the same 1px sage edge and the same 10px
# corner, so a menu reads as a pane dropped out of the pane it came from.
name = "Forest"

font = "Ubuntu Sans"
font_size = 13.0

# Sea green against pale birch. The accent is dark enough that kOnAccent's
# white sits on it at better than 4:1, which is what lets it fill a button
# rather than only outline one.
accent               = "#2E8B57"
foreground           = "#E8F2EA"
surface_hover        = "#1F4433"
surface_pressed      = "#2A6B4C"
workspace_background = "#101A15"
popup_background     = "#F2121C16"
popup_foreground     = "#E8F2EA"
control_surface      = "#1A2A21"
slider_track         = "#2A6B4C"
# Secondary text is a desaturated sage rather than the accent: this theme's
# accent is a fill colour, and reusing it for muted labels would put the one
# saturated green in the palette on the least important text in the shell.
muted                = "#8AA79A"
divider              = "#33E8F2EA"
scrim                = "#88101A15"

# The bar fades sea green -> pine -> forest floor, all at panel_background's
# alpha, so the bright end sits against the screen edge and the fade cannot
# band across the middle.
panel_background     = "#EE0E1712"
panel_gradient       = true

# A 6px gap on every anchored edge, cut by a real gtk-layer-shell margin so
# nothing tiles into it and a click that lands there still reaches the desktop.
# The rim is the point of the theme: a hairline of lit sage around a dark bar.
panel_margin         = 6
panel_radius         = 10.0
panel_border         = "#594FB183"
panel_border_width   = 1.0

# The same material as the bar: same corner, same rim.
popup_radius         = 10.0
popup_border         = "#594FB183"
popup_border_width   = 1.0

# Its popups float too, for glassy's reason rather than graceful's: this bar
# is lifted off the screen by panel_margin, so a menu glued to it would be the
# only thing in the picture touching anything, and matching that margin keeps
# the two gaps equal. It would also cost the rim on the joined edge — the one
# lit line this theme is built around — which an attached popup drops so no
# seam crosses the join. popup_attach_radius is therefore unread here, and
# spelled only because every theme spells every key.
popup_gap            = 6.0
popup_attach_radius  = 0.0

# The lift is tinted with the theme's own darkest green rather than pure black,
# so a card floating over a wallpaper drops a shadow that belongs to the
# palette instead of a grey one.
popup_shadow_color   = "#73060C09"
popup_shadow_blur    = 20.0
popup_shadow_spread  = -1.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 8.0

# A floating card has no join to travel out of, so it grows into place from its
# own centre instead — the softer arrival this theme's rounder corners want.
popup_animation      = "scale"
''';

const String _dracula = '''
# Dracula — the canonical palette (https://draculatheme.com).
#
# Roles: purple is the accent, current-line (#44475A) carries hovers and card
# surfaces, comment (#6272A4) is both the pressed state and secondary text.
# The bar therefore fades purple -> slate -> near-black.
name = "Dracula"

font = "Ubuntu Sans"
font_size = 13.0

accent               = "#BD93F9"
foreground           = "#F8F8F2"
surface_hover        = "#44475A"
surface_pressed      = "#6272A4"
workspace_background = "#282A36"
popup_background     = "#282A36"
popup_foreground     = "#F8F8F2"
control_surface      = "#44475A"
slider_track         = "#6272A4"
muted                = "#6272A4"
divider              = "#33F8F8F2"
scrim                = "#88282A36"

panel_background     = "#EE282A36"
panel_gradient       = true

# Flush and square, like graceful — Dracula is a flat palette, not a floating
# one. The rim colour matches divider so switching it on reads as Dracula.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33F8F8F2"
panel_border_width   = 0.0

# The same card shape as graceful; the rim takes Dracula's own divider.
popup_radius         = 8.0
popup_border         = "#33F8F8F2"
popup_border_width   = 1.0

# Attached to the bar, as graceful is.
popup_gap            = 0.0
popup_attach_radius  = 0.0

# The same lift as graceful, tinted with Dracula's own background rather than
# pure black so it reads as part of the palette.
popup_shadow_color   = "#66191A21"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0

# Attached to the bar, so it slides out of it, as graceful does.
popup_animation      = "slide"
''';

const String _glassy = '''
# Glassy — translucent surfaces that let the wallpaper through.
#
# The effect comes from alpha, not from blur: a layer-shell surface is
# transparent and the compositor owns everything beneath it, so Flutter cannot
# blur the desktop. Surfaces are white-alpha rather than opaque greys so they
# tint whatever is behind them instead of covering it.
#
# popup_background keeps a high alpha on purpose — a popup has to stay legible
# over a light wallpaper, where a fully translucent card would not.
name = "Glassy"

font = "Ubuntu Sans"
font_size = 13.0

accent               = "#7FB6FF"
foreground           = "#F5F7FA"
surface_hover        = "#33FFFFFF"
surface_pressed      = "#4DFFFFFF"
workspace_background = "#33101318"
popup_background     = "#B0141821"
popup_foreground     = "#F5F7FA"
control_surface      = "#26FFFFFF"
slider_track         = "#40FFFFFF"
muted                = "#99EAF0F8"
divider              = "#26FFFFFF"
scrim                = "#66101318"

# No gradient: a sheet of glass, not a coloured fade. A gradient here would
# put the accent against the screen edge at the bar's own opacity, which is
# the one place this theme wants nothing but the wallpaper.
panel_background     = "#40121722"
panel_gradient       = false

# A floating pane rather than a strip: an 8px gap on every anchored edge, cut
# by a real gtk-layer-shell margin, so nothing tiles into the gap (the
# compositor folds the margin into the bar's reserved space) and clicks that
# land in it still reach the desktop. The 1px rim is what gives an edge to a
# sheet this translucent — without it the bar has no boundary at all over a
# busy wallpaper.
panel_margin         = 8
panel_radius         = 12.0
panel_border         = "#40FFFFFF"
panel_border_width   = 1.0

# Popups are the bar's material: the same 12px corner and the same rim, so a
# menu reads as a pane dropped out of the pane it came from. The rim is
# panel_border rather than the softer `divider` — a card floating over a busy
# wallpaper needs an edge, not a hairline.
popup_radius         = 12.0
popup_border         = "#40FFFFFF"
popup_border_width   = 1.0

# The one theme whose popups float. Its bar already floats — panel_margin is 8 —
# so a menu glued to that bar would be the only thing on screen touching
# anything; matching the margin keeps the two gaps equal. Attaching would also
# expose the seam a translucent card cannot avoid: popup_background is #B0 and
# panel_background is #40, so at a zero gap the two fills composite separately
# against the wallpaper and the join shows a step in tone — which a flare would
# only make wider. popup_attach_radius is therefore unread here, and spelled
# only because every theme spells every key.
popup_gap            = 8.0
popup_attach_radius  = 0.0

# The theme the shadow matters most to: a translucent card over a busy
# wallpaper has almost no edge of its own, so the lift is deeper and softer than
# the flat themes'. The negative spread pulls the shape back in a little, which
# keeps a wide blur from reading as a halo around the card.
popup_shadow_color   = "#59000000"
popup_shadow_blur    = 28.0
popup_shadow_spread  = -2.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 10.0

# Its bar floats and its popups float with it, so there is no edge to unroll
# out of: the card simply fades up, which is also the arrival that shows least
# of the seam a translucent fill draws over a moving wallpaper.
popup_animation      = "fade"
''';

const String _midnight = '''
# Midnight — a lit theme: the shell glows rather than casting shadows.
#
# Every other shipped theme drops its cards *onto* the desktop. The shadow is
# near-black, it is displaced downward, and its spread is zero or negative — a
# sheet of paper lying on a table. This one lights them from within instead:
# the shadow takes the accent's own indigo, it is displaced on neither axis,
# and its spread is *positive*, so what surrounds a card is a symmetrical bloom
# rather than a shadow falling away from it. Same key, spent on light.
#
# It is also the first shipped theme to treat the *type scale* as part of the
# palette. `font_size` is the body tier and every other size in the shell is a
# fixed ratio to it, so 14 is not "bigger labels" — it is the whole shell set
# one rung up, at a size these low-contrast blues can carry without their thin
# strokes closing up. One rung and not a leap, because panel thickness is not a
# theme key: a bar left at its default height crops a much larger font.
name = "Midnight"

font = "Ubuntu Sans"
font_size = 14.0

# Moonlight over deep water. The accent is an indigo dark enough to hold
# kOnAccent's white at better than 4:1 — it fills buttons as well as outlining
# them — and it is the only fully saturated colour in the theme: everything
# else is a blue so dark it reads as black, or the pale blue-white the text is
# set in. `muted` is a soft periwinkle grey rather than the accent, forest's
# rule: the one vivid colour in a palette does not belong on its least
# important text.
accent               = "#4C6EF5"
foreground           = "#E4E9FF"
surface_hover        = "#232C52"
surface_pressed      = "#33407A"
workspace_background = "#0A0F22"
popup_background     = "#E6111730"
popup_foreground     = "#E4E9FF"
control_surface      = "#1C2340"
slider_track         = "#33407A"
muted                = "#8E9AC8"
# The one divider in the shell that is not white at low alpha. A neutral
# hairline over these blues reads as grey dust on the surface; a periwinkle one
# reads as the same light everything else in this theme is lit by.
divider              = "#4C8098FF"
# The deepest scrim shipped. An overlay here is the lights going out, not a
# wash over what is behind it — which is what lets a panel of small text be
# read over a bright wallpaper at this little contrast.
scrim                = "#A6050816"

# The bar fades indigo -> deep blue -> midnight, every stop at
# panel_background's own alpha.
panel_background     = "#F00A0F22"
panel_gradient       = true

# The most lifted bar shipped: a 12px gap on every anchored edge, an 18px
# corner, and a rim half again as thick as a hairline. All three go together —
# at this radius a 1px rim thins out visibly around the corners, and the rim is
# what gives a dark bar an edge against a dark wallpaper.
panel_margin         = 12
panel_radius         = 18.0
panel_border         = "#665F87F5"
panel_border_width   = 1.5

# The bar's own material, so a menu reads as a pane dropped out of the pane it
# came from: the same corner, the same rim, the same weight of it.
popup_radius         = 18.0
popup_border         = "#665F87F5"
popup_border_width   = 1.5

# Its popups float, and the gap matches the bar's own margin so the two
# distances in the picture are one distance. That is also what gives the glow
# somewhere to land: on the joined edge the shadow's margin is clamped to the
# gap, so the bloom fills the 12px between card and bar and is cut exactly at
# the panel. popup_attach_radius is unread at any gap above zero, and spelled
# only because every shipped theme spells every key.
popup_gap            = 12.0
popup_attach_radius  = 0.0

# The glow. Three things make it one rather than a shadow, and all three are
# unique to this theme: the colour is the accent's indigo rather than black,
# both offsets are zero, so it surrounds the card instead of falling from it,
# and the spread is *positive*, so the bloom starts outside the card's edge
# rather than being pulled back inside it the way glassy pulls its halo in.
# The reach the shell grows each popup's window by is blur + spread on every
# side equally, which is the geometric statement of the same thing.
popup_shadow_color   = "#734C6EF5"
popup_shadow_blur    = 26.0
popup_shadow_spread  = 3.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 0.0

# Its popups float, at the same distance its bar does, so an entrance here has
# a gap to cross rather than a seam to open along: the card travels that 12px
# out of the bar under a fade, which is the arrival that reads as the menu
# coming from its button rather than merely appearing beside it. The glow comes
# with it, and being symmetrical on both axes it is the one lift in the shell
# that no direction of travel can contradict — which is why this theme need not
# take glassy's way out and simply fade.
popup_animation      = "slide"
''';

const String _carbon = '''
# Carbon — machined graphite: flat, square, and joined.
#
# The flattest thing this engine can express, and every key here is spent
# saying so. No gradient on the bar, no margin under it, no corner on it, no
# alpha in it — and, the one shipped theme that goes this far, no shadow under
# any card at all. popup_shadow_color's alpha is the documented off switch, and
# switching it off gives back the exact popup geometry of a shell built before
# shadows existed: nothing in this theme floats over anything, because nothing
# in it is lifted.
#
# What carries the weight instead is the join. Every bar popup is attached
# (popup_gap = 0) and flared (popup_attach_radius = 12), so a menu does not
# appear beside the bar — it *grows out of* it, each side sweeping outward as
# it reaches the panel, widest exactly where the two meet. A flat theme with
# one piece of shaping in it puts that shaping where the eye already is. The
# bar and the cards then carry one rim, of one colour and one width, and the
# flare reaches back into the bar far enough to join the two: the line runs
# along the panel edge, bends off it where a menu is open, goes round the card
# and comes back. It is the only line in the theme, and the only thing that
# gives a flat surface an edge over a dark wallpaper.
#
# And because a card that grows out of the bar is made of the same material as
# the bar, popup_background is panel_background exactly: the join has no colour
# step across it, so the two surfaces read as one piece of graphite the menu
# was cut out of rather than as a card resting against a strip. Every other
# shipped theme lifts its popups a shade off the bar because a shadow and a gap
# separate them anyway; this one has neither, so the shade would be the only
# thing left saying they are two surfaces.
#
# The palette is IBM's Carbon greys, which is where the name comes from and
# also why it is the right one: that design language is flat by conviction
# rather than by omission. Interactive blue on graphite, and nothing else
# coloured anywhere.
name = "Carbon"

font = "Ubuntu Sans"
font_size = 13.0

# Gray 100 for the deepest surface — the bar and every card alike — Gray 80 and
# Gray 70 for the states, Gray 40 for secondary text, Gray 10 for text. Blue 60
# is the one colour, and it is the darker interactive blue rather than the
# lighter one so kOnAccent's white clears 4.5:1 on top of it. Carbon's Gray 100
# theme layers a card one step up from its background, and skipping that step
# is the deliberate part: a control on a card still elevates (control_surface
# is Gray 80, so it now steps twice), but the card itself does not, because a
# card that grew out of the bar has nothing to elevate away from.
accent               = "#0F62FE"
foreground           = "#F4F4F4"
surface_hover        = "#393939"
surface_pressed      = "#525252"
workspace_background = "#161616"
popup_background     = "#161616"
popup_foreground     = "#F4F4F4"
control_surface      = "#393939"
slider_track         = "#525252"
muted                = "#A8A8A8"
# An opaque rule, not a wash: every other theme's divider is white at low alpha
# and takes its tone from whatever it happens to be drawn over. A flat theme
# draws a line of a known colour instead — Carbon's border-subtle, one step up
# from the card it separates.
divider              = "#393939"
scrim                = "#A6161616"

# A solid sheet of Gray 100 across the screen edge: no fade, and the only bar
# shipped with no alpha at all. A gradient would put the accent against the
# screen edge, and a translucent bar would let the wallpaper decide what colour
# the flattest surface in the theme is — and, since popup_background is this
# same value, what colour every menu in the theme is with it. The two keys are
# a pair here: an alpha or a gradient on either one alone puts a visible step
# back across the join.
panel_background     = "#161616"
panel_gradient       = false

# Flush and square, and rimmed. A bar with panel_border_width above zero draws
# that rim along its *inner* edge too, so a menu attached to it used to butt
# straight into a hairline running across its own mouth: the card read as
# something taped underneath a line rather than as the bar opening. Any attached
# card now reaches one rim-width back into the panel, so its own fill takes that
# hairline out across the whole mouth; what the flare below adds is how the line
# resumes at either end — the two arcs pick it up and carry it down the card's
# sides rather than meeting them square. What is left is one continuous outline,
# which is why the rim is worth having here at all: with no shadow anywhere in
# this theme and no colour step across the join, an edge drawn all the way round
# the bar and its menus is the only thing separating either from the wallpaper.
#
# It is Carbon's border-strong, and it is popup_border exactly. The two are a
# pair for the same reason panel_background and popup_background are: the line
# turns the corner from one surface onto the other, so a different colour or a
# different width on either side would put a visible step at the two points
# where it does.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#525252"
panel_border_width   = 1.0

# A 4px corner: the smallest rounding that still reads as deliberate, on the
# two corners away from the join. The rim is Carbon's border-strong rather than
# the divider's border-subtle, because with no shadow beneath it and no colour
# step against the bar the rim is the card's only edge — over a dark wallpaper
# a subtle one would leave it with none, and along the flare it is the only
# thing that draws the sweep at all, since the fill either side of it is now
# the same graphite. It is panel_border to the value, and the width matches
# too: the collar lays the flare's stroke over the very band the bar's rim
# occupies, so equal widths make one line where unequal ones would make a
# step in it.
popup_radius         = 4.0
popup_border         = "#525252"
popup_border_width   = 1.0

# The theme's one piece of shaping. The gap is zero, so the card is flush and
# the two corners on the join square off; the flare then sweeps those two sides
# outward into the bar. It paints outside the card's own box, so the shell
# grows the popup's window by it — which here is the *whole* of that margin,
# since the shadow contributes none — plus one panel_border_width on the join
# itself, which is the reach that lays the card's fill over the bar's rim. Zero
# here would give the flat butt join back: still seamless, since that reach is
# the join's rather than the flare's, but with the bar's line meeting the card's
# sides square instead of sweeping into them.
popup_gap            = 0.0
popup_attach_radius  = 12.0

# No shadow, and no margin for one. The alpha is the off switch; the four
# numbers under it are held at zero so the file says the same thing twice
# rather than leaving a shadow's dimensions lying around for a later edit to
# switch on by accident.
popup_shadow_color   = "#00000000"
popup_shadow_blur    = 0.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 0.0

# The card is flush with the bar and flared into it, so its entrance is a
# travel out of that join rather than an arrival beside it — the same slide the
# other two attached themes play, and the one that reads as the bar opening.
popup_animation      = "slide"
''';
