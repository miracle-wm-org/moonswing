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
  'glassy': _glassy,
  'forest': _forest,
  'autumn': _autumn,
  'dracula': _dracula,
  'midnight': _midnight,
  'carbon': _carbon,
};

const String _forest = '''
# Forest — a timber beam on capstones, overgrown, with every menu a trunk.
#
# The one shipped theme that is made of something. The bar is a plank of
# oak (panel_texture) carved with a lit top edge and a shadowed lip
# (panel_bevel), sitting on a mossy capstone at each end (panel_end_*), and
# the woods have got to it: ivy hangs off its inner edge, moss drips from it,
# ferns spring from the stones and amber berries catch the light among the
# leaves (panel_foliage). The leaves hang past the bar and over the windows
# beneath it — the bar's surface grows by panel_overhang to hold them, and
# that strip is cut out of its input region, so the leaves are paint and a
# click on one lands on the window behind it.
#
# Every menu is a tree. It is attached (popup_gap = 0) so it grows out of the
# bar rather than floating by it; its join flares like a trunk's foot
# (popup_attach_radius); its rim is a thick band of bark (popup_border_*)
# around a dark heartwood card with the faintest grain in it; roots spread
# along the beam on either side of it (popup_roots); and it *grows* into
# place, narrow and crowned at first and thickening as it rises
# (popup_animation = "sprout"), while the leaves around its mouth shiver.
#
# None of it is an asset. The wood, the stones, the bark and every leaf are
# drawn from seeded arithmetic (lib/decor/), so this file is the whole theme.
name = "Forest"

font = "Ubuntu Sans"
font_size = 13.0
icon_pack = "font_awesome"

# Sea green: the one saturated green, spent on what is active. Dark enough to
# carry kOnAccent's white, so it fills a button rather than only outlining one.
accent               = "#2E8B57"
# Birch-pale parchment, which holds its contrast on oak and on heartwood alike.
foreground           = "#F4EDDD"
# Moss over wood: a hovered button on the beam is a patch of moss on it.
surface_hover        = "#4A6B35"
surface_pressed      = "#5E8743"
workspace_background = "#2B3A22"
popup_background     = "#F51A1610"
popup_foreground     = "#F4EDDD"
control_surface      = "#2C2A1E"
slider_track         = "#4A5E35"
# Lichen: a pale, greyed sage for the secondary tier, never the accent.
muted                = "#B5B39A"
divider              = "#33F4EDDD"

# Amber — the berries' colour, so "unread" is the warmest thing in the woods.
notification_badge   = "#F0A53A"
notification_badge_foreground = "#231708"
scrim                = "#8A0E120B"

# The beam is opaque oak: the panel's own fill is the dark under the grain,
# and the gradient is off because the wood is the picture.
panel_background     = "#FF1E150D"
panel_gradient       = false

# A floating beam, so the leaves hang from something that is visibly hung.
panel_margin         = 6
panel_radius         = 7.0
# A dark bark line round the beam, broken where a trunk grows out of it.
panel_border         = "#E61A0F07"
panel_border_width   = 1.5

panel_texture        = "wood"
panel_texture_color  = "#FF6E4A2A"
panel_end_texture    = "stone"
panel_end_color      = "#FF6C7166"
panel_end_length     = 54.0
panel_bevel          = 0.85
panel_image          = ""

panel_foliage        = "wildwood"
foliage_color        = "#3F7D38"
foliage_bloom        = "#E8A33C"
foliage_density      = 1.0
# How far the leaves may hang over the windows below the beam.
panel_overhang       = 64

# The menu is the trunk: a thick bark rim around heartwood with a ghost of
# grain, its corners rounded like a trunk seen side on, and a foot that flares
# into the beam.
popup_radius         = 12.0
popup_gap            = 0.0
popup_attach_radius  = 14.0
popup_border         = "#FF4A3322"
popup_border_width   = 9.0
popup_texture        = "wood"
popup_texture_color  = "#1C7A5636"
popup_border_texture = "bark"
popup_border_texture_color = "#FF6B5340"
popup_image          = ""
popup_roots          = 34.0

# Shade under the canopy: a deep, soft shadow tinted with the forest floor.
popup_shadow_color   = "#99070A05"
popup_shadow_blur    = 22.0
popup_shadow_spread  = -2.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 10.0

# Unhurried, because a tree is: the trunk takes a third of a second to rise.
popup_animation      = "sprout"
popup_animation_duration = 320

overlay_radius       = 14.0

# The overlays lift into place, a little more slowly than the default, and
# leave faster than they came.
overlay_animation    = "rise"
overlay_animation_duration = 220
overlay_animation_exit_ratio = 0.8
overlay_animation_curve = "ease_out"
''';

const String _autumn = '''
# Autumn — a chestnut beam between two log ends, at the turn of the year.
#
# Forest's sibling, in October. The bar is a plank of chestnut, planed smooth
# (panel_texture, a warm tint over a dark fill, so the grain is there but
# quiet) and carved along its edges (panel_bevel), between two sawn log ends
# in bark (panel_end_*). What grows off it is the harvest (panel_foliage):
#
#  * on a top or side bar, the two corners of the screen are framed in
#    turning leaves: a heap of maple and oak tucked under the bar's ends
#    against the screen's very edge and spilling down its side, thickest in
#    the corner and ragged at its rim, with a few short branches buried in it
#    and a few loose leaves on their way down. Every leaf is somewhere between
#    foliage_color's green and foliage_bloom's orange and past it, so they
#    come out russet, scarlet, gold, brown and claret, with the odd one
#    still green. The middle of the bar is left bare.
#  * on a bottom bar, pumpkin patches sit along its edge: one in each corner
#    and a few between, each a vine with its tendrils, big lobed leaves on
#    stalks, pumpkins mostly in foliage_bloom (with a deep red one, a golden
#    one, a pale one, now and then a green squash), and fallen leaves among
#    them.
#
# As in forest, the overhang is cut out of the bar's input region: the
# leaves and the pumpkins are paint, and a click on one lands on the window
# behind it.
#
# Every menu is a tree, the way forest's are: attached, flared at the foot,
# rimmed in bark around a dark walnut card, rooted along the beam, and grown
# into place (popup_animation = "sprout").
#
# None of it is an asset. The wood, the bark, every leaf and every pumpkin
# are drawn from seeded arithmetic (lib/decor/), so this file is the whole
# theme.
name = "Autumn"

font = "Ubuntu Sans"
font_size = 13.0

# Burnt orange: the season's colour, spent on what is active. Dark enough to
# carry kOnAccent's white, so it fills a button rather than only outlining it.
accent               = "#B5541C"
# Cream, which holds its contrast on chestnut and on walnut alike.
foreground           = "#F7EAD3"
# Toasted chestnut: a hovered button on the beam is a lighter patch of it.
surface_hover        = "#6E4627"
surface_pressed      = "#84552F"
workspace_background = "#3B2716"
popup_background     = "#F51F140B"
popup_foreground     = "#F7EAD3"
control_surface      = "#33241A"
slider_track         = "#6A4A2E"
# Wheat: a pale, dry tan for the secondary tier, never the accent.
muted                = "#C9AE8A"
divider              = "#33F7EAD3"

# A clear October sky: the one cool colour in the theme, so "unread" is
# never mistaken for another leaf.
notification_badge   = "#6FA8DC"
notification_badge_foreground = "#0F1E2C"
scrim                = "#8A140C06"

# The beam is opaque: the panel's own fill is the dark under the chestnut,
# and the gradient is off because the wood is the picture.
panel_background     = "#FF2A190D"
panel_gradient       = false

# Flush with the screen's edges, so the leaves framing its corners start at
# its side edge rather than a margin's width inside it. The radius
# rounds only the inner corners of a flush bar.
panel_margin         = 0
panel_radius         = 8.0
# A dark line round the beam, broken where a trunk grows out of it.
panel_border         = "#E6180C04"
panel_border_width   = 1.5

# Chestnut at nine tenths, over the dark fill: the grain softened rather than
# gone, which is what reads as a smooth brown.
panel_texture        = "wood"
panel_texture_color  = "#E68A5530"
panel_end_texture    = "bark"
panel_end_color      = "#FF6A4E36"
panel_end_length     = 44.0
panel_bevel          = 0.7
panel_image          = ""

panel_foliage        = "harvest"
# What is still green: the pumpkin vines, and the last few leaves to turn.
foliage_color        = "#6B8A35"
# What has turned: the leaves are toned off it, the pumpkins are it.
foliage_bloom        = "#E2731E"
foliage_density      = 1.0
# Room for the corner heaps to spill a little way down the screen's sides.
# A pumpkin stops growing long before it.
panel_overhang       = 130

# The menu is the trunk: a thick bark rim around walnut with a ghost of
# grain, rounded like a trunk seen side on, with a foot that flares into the
# beam.
popup_radius         = 12.0
popup_gap            = 0.0
popup_attach_radius  = 14.0
popup_border         = "#FF4E3420"
popup_border_width   = 9.0
popup_texture        = "wood"
popup_texture_color  = "#1C8A5530"
popup_border_texture = "bark"
popup_border_texture_color = "#FF6E5038"
popup_image          = ""
popup_roots          = 30.0

# A long, warm shadow, as from a low autumn sun.
popup_shadow_color   = "#990A0603"
popup_shadow_blur    = 22.0
popup_shadow_spread  = -2.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 10.0

# Unhurried, as forest is: the trunk takes a third of a second to rise.
popup_animation      = "sprout"
popup_animation_duration = 320

overlay_radius       = 14.0

# The overlays drift into place and leave faster than they came.
overlay_animation    = "rise"
overlay_animation_duration = 220
overlay_animation_exit_ratio = 0.8
overlay_animation_curve = "ease_out"
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
icon_pack = "font_awesome"

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

# Dracula's own orange, from the palette the rest of this theme is taken from,
# so the loudest thing in the shell is still a Dracula colour.
notification_badge   = "#FFB86C"
notification_badge_foreground = "#282A36"
scrim                = "#88282A36"

# Solid, not translucent: a see-through bar would let the wallpaper decide
# what colour the flattest surface in the theme is.
panel_background     = "#FF282A36"
panel_gradient       = false

# Flush and square — Dracula is a flat palette, not a floating one. The rim
# colour matches divider so switching it on reads as Dracula.
panel_margin         = 0
panel_radius         = 0.0
panel_border         = "#33F8F8F2"
panel_border_width   = 0.0

# The shell's default card shape; the rim takes Dracula's own divider.
popup_radius         = 8.0
popup_border         = "#33F8F8F2"
popup_border_width   = 1.0

# Attached to the bar.
popup_gap            = 0.0
popup_attach_radius  = 0.0

# The shell's default lift, tinted with Dracula's own background rather than
# pure black so it reads as part of the palette.
popup_shadow_color   = "#66191A21"
popup_shadow_blur    = 16.0
popup_shadow_spread  = 0.0
popup_shadow_offset_x = 0.0
popup_shadow_offset_y = 6.0

# Attached to the bar, so it slides out of it.
popup_animation      = "slide"
popup_animation_duration = 140

overlay_radius       = 12.0

# Overlays come towards you and settle a fraction past their resting size.
# The overshoot is read backwards on the way out, so they dip before they
# go.
overlay_animation    = "zoom"
overlay_animation_duration = 170
overlay_animation_exit_ratio = 0.85
overlay_animation_curve = "overshoot"
# Made of nothing but colour: no material, no end caps, no carve, no picture,
# nothing growing off the bar and no roots under the menus. Spelled anyway,
# because a shipped theme leans on no default.
panel_texture        = "none"
panel_texture_color  = "#FF6B4A2E"
panel_end_texture    = "none"
panel_end_color      = "#FF6E726B"
panel_end_length     = 0.0
panel_bevel          = 0.0
panel_image          = ""
panel_foliage        = "none"
foliage_color        = "#FF3E7A3A"
foliage_bloom        = "#FFE0A13A"
foliage_density      = 1.0
panel_overhang       = 0
popup_texture        = "none"
popup_texture_color  = "#206B4A2E"
popup_border_texture = "none"
popup_border_texture_color = "#FF5A4030"
popup_image          = ""
popup_roots          = 0.0
''';

const String _glassy = '''
# Glassy — translucent surfaces that let the wallpaper through.
#
# The effect comes from alpha, not from blur: a layer-shell surface is
# transparent and the compositor owns everything beneath it, so Flutter cannot
# blur the desktop. Surfaces are white-alpha rather than opaque greys so they
# tint whatever is behind them instead of covering it (control_surface aside —
# see there).
#
# popup_background keeps a high alpha on purpose — a popup has to stay legible
# over a light wallpaper, where a fully translucent card would not.
name = "Glassy"

font = "Ubuntu Sans"
font_size = 13.0
icon_pack = "font_awesome"

accent               = "#7FB6FF"
foreground           = "#F5F7FA"
surface_hover        = "#33FFFFFF"
surface_pressed      = "#4DFFFFFF"
workspace_background = "#33101318"
popup_background     = "#B0141821"
popup_foreground     = "#F5F7FA"
# The one surface that is black-alpha rather than white. Controls — inputs,
# cards, tiles — nest inside one another, and a translucent tint adds up once
# per layer: at #26FFFFFF a dropdown inside a binding card in Settings came out
# a mid grey under white text. Dark, a nested control sinks a little further
# into the card instead of lighting up; the divider rim still gives it an edge.
control_surface      = "#33000000"
slider_track         = "#40FFFFFF"
muted                = "#99EAF0F8"
divider              = "#26FFFFFF"

# Warm amber under a cold blue theme. It is also the one fully opaque colour in
# a translucent theme, which is deliberate: the card floats over the wallpaper
# rather than over a surface of the shell's own.
notification_badge   = "#FFCB6B"
notification_badge_foreground = "#141821"
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
popup_animation_duration = 140

overlay_radius       = 12.0

# Glass dissolves rather than moves: opacity alone, eased at both ends and
# given longer than the default, because a fade with nothing else in it is
# the one effect a short duration hides completely.
overlay_animation    = "fade"
overlay_animation_duration = 220
overlay_animation_exit_ratio = 1.0
overlay_animation_curve = "ease_in_out"
# Made of nothing but colour: no material, no end caps, no carve, no picture,
# nothing growing off the bar and no roots under the menus. Spelled anyway,
# because a shipped theme leans on no default.
panel_texture        = "none"
panel_texture_color  = "#FF6B4A2E"
panel_end_texture    = "none"
panel_end_color      = "#FF6E726B"
panel_end_length     = 0.0
panel_bevel          = 0.0
panel_image          = ""
panel_foliage        = "none"
foliage_color        = "#FF3E7A3A"
foliage_bloom        = "#FFE0A13A"
foliage_density      = 1.0
panel_overhang       = 0
popup_texture        = "none"
popup_texture_color  = "#206B4A2E"
popup_border_texture = "none"
popup_border_texture_color = "#FF5A4030"
popup_image          = ""
popup_roots          = 0.0
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
icon_pack = "font_awesome"

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

# Yellow against indigo. This theme's accent is a blue among blues, so an
# unread notification is the one thing on screen that is not part of the night.
notification_badge   = "#FFD43B"
notification_badge_foreground = "#0A0F22"
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
popup_animation_duration = 140

overlay_radius       = 12.0

# The statliest arrival of the shipped themes, on the asymmetric curve:
# a sharp departure into a long settle, and out again in three quarters of
# the time.
overlay_animation    = "scale"
overlay_animation_duration = 260
overlay_animation_exit_ratio = 0.75
overlay_animation_curve = "emphasized"
# Made of nothing but colour: no material, no end caps, no carve, no picture,
# nothing growing off the bar and no roots under the menus. Spelled anyway,
# because a shipped theme leans on no default.
panel_texture        = "none"
panel_texture_color  = "#FF6B4A2E"
panel_end_texture    = "none"
panel_end_color      = "#FF6E726B"
panel_end_length     = 0.0
panel_bevel          = 0.0
panel_image          = ""
panel_foliage        = "none"
foliage_color        = "#FF3E7A3A"
foliage_bloom        = "#FFE0A13A"
foliage_density      = 1.0
panel_overhang       = 0
popup_texture        = "none"
popup_texture_color  = "#206B4A2E"
popup_border_texture = "none"
popup_border_texture_color = "#FF5A4030"
popup_image          = ""
popup_roots          = 0.0
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
icon_pack = "font_awesome"

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

# Carbon's support-warning yellow, from IBM's own palette — the token that
# system means by "something is waiting for you".
notification_badge   = "#F1C21B"
notification_badge_foreground = "#161616"
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
# something taped underneath a line rather than as the bar opening. The
# compositor places a menu *below* the bar and never over it, so nothing the
# card paints can reach that line; the bar leaves it out itself instead, across
# exactly the stretch an open menu's mouth covers. What the flare below adds is
# how the line resumes at either end — the two arcs pick it up and carry it down
# the card's sides rather than meeting them square. What is left is one continuous outline,
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
# too: the card's own stroke picks the line up exactly where the break in the
# bar's rim leaves off, so equal widths make one line where unequal ones would
# make a step in it.
popup_radius         = 4.0
popup_border         = "#525252"
popup_border_width   = 1.0

# The theme's one piece of shaping. The gap is zero, so the card is flush and
# the two corners on the join square off; the flare then sweeps those two sides
# outward into the bar. It paints outside the card's own box, so the shell
# grows the popup's window by it — which here is the *whole* of that margin,
# since the shadow contributes none. It also widens the break the bar leaves in
# its own rim, because the flare is how wide the join actually is. Zero here
# would give the flat butt join back: still seamless, since the break is what
# takes the bar's line out of the mouth either way, but with that line meeting
# the card's sides square instead of sweeping into them.
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
popup_animation_duration = 140

overlay_radius       = 12.0

# Overlays unfold out of their own middle, keeping their width — the
# flat-panel counterpart to the popups this theme attaches to the bar,
# and quick, because nothing here is meant to read as floating.
overlay_animation    = "unfold"
overlay_animation_duration = 140
overlay_animation_exit_ratio = 0.75
overlay_animation_curve = "ease_out"
# Made of nothing but colour: no material, no end caps, no carve, no picture,
# nothing growing off the bar and no roots under the menus. Spelled anyway,
# because a shipped theme leans on no default.
panel_texture        = "none"
panel_texture_color  = "#FF6B4A2E"
panel_end_texture    = "none"
panel_end_color      = "#FF6E726B"
panel_end_length     = 0.0
panel_bevel          = 0.0
panel_image          = ""
panel_foliage        = "none"
foliage_color        = "#FF3E7A3A"
foliage_bloom        = "#FFE0A13A"
foliage_density      = 1.0
panel_overhang       = 0
popup_texture        = "none"
popup_texture_color  = "#206B4A2E"
popup_border_texture = "none"
popup_border_texture_color = "#FF5A4030"
popup_image          = ""
popup_roots          = 0.0
''';
