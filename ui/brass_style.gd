class_name BrassStyle
## The steampunk brass look shared by the HUD and the menus (inventory, crafting, build menu,
## pause, title): frames for panels, slots, buttons, key badges and bars, and colours.
##
## Art in res://assets/ui/ (anything missing is drawn in code instead):
##   plaque.png        974 x 673: the menus' and HUD panels' frame, 9-sliced just inside its
##                     corner rivets (PLAQUE_SLICE), edges stretched, drawn at MENU_FRAME_SCALE
##                     (menus) or SMALL_FRAME_SCALE (the build placement panel)
##   panel_frame.png   1024 x 562: the ornate frame, for the title screen only (TITLE_SLICE)
##   action_bar.png, slot_plain.png, slot_gear.png   the action bar (see ActionBar)
##   compass_clock.png the compass with the small clock (see CompassClock)
##   vitals_panel.png  the hunger and warmth panel with its gauge (see VitalsPanel)
##   crosshair.png     drawn at 32 px (see HudInstruments)

const UI_FOLDER := "res://assets/ui/"

const TEXT := Color(0.94, 0.86, 0.68)
const TEXT_DIM := Color(0.72, 0.64, 0.5)
const BAD := Color(1.0, 0.38, 0.3)
const BRASS := BrassFrame.BRASS
const BRASS_LIGHT := BrassFrame.BRASS_LIGHT
const BRASS_DARK := BrassFrame.BRASS_DARK
const SHADOW := BrassFrame.SHADOW
## Panels: flat dark brown (#2a2118) at 92%
const PANEL := Color(0.165, 0.13, 0.094, 0.92)
## Slots: darker, sunk into the panel
const SLOT := Color(0.075, 0.058, 0.042, 0.96)
const SLOT_SELECTED := Color(0.13, 0.095, 0.06, 0.97)
const RAIL := Color(0.07, 0.055, 0.04, 0.7)
const BUTTON := Color(0.24, 0.17, 0.1)
const BUTTON_HOVER := Color(0.31, 0.22, 0.13)
const BAR_BACK := Color(0.06, 0.05, 0.04, 0.95)
const HUNGER_FILL := Color(0.86, 0.62, 0.26)
const WARMTH_FILL := Color(0.92, 0.38, 0.16)
## The key badges: dark brown with a thin brass border
const BADGE_FILL := Color(0.2, 0.13, 0.08, 0.92)
## How faint the gear in an empty inventory or chest slot is
const GEAR_ALPHA := 0.15

## plaque.png: 9-slice margins (left, top, right, bottom, in its pixels: just inside the corner
## rivets) and where its flat middle starts (the content margin before scaling)
const PLAQUE_SLICE := Vector4(60, 58, 60, 58)
const PLAQUE_INSIDE := Vector2(30, 28)
const MENU_FRAME_SCALE := 0.4
const SMALL_FRAME_SCALE := 0.3
## panel_frame.png (the title screen): 9-slice margins at the inner edge of its ornate corners,
## where its leather middle starts, and how big it's drawn
const TITLE_SLICE := Vector4(232, 222, 232, 232)
const TITLE_INSIDE := Vector2(135, 150)
const TITLE_FRAME_SCALE := 0.24
## Each kind of frame and how it looks
const KINDS := {
	"panel": {"band": 3.0, "radius": 4.0, "rivets": true, "vignette": true, "fill": PANEL, "margin": Vector2(20, 16)},
	"plate": {"band": 2.0, "radius": 3.0, "rivets": true, "vignette": true, "fill": PANEL, "margin": Vector2(12, 7)},
	"action_bar": {"band": 2.0, "radius": 4.0, "rivets": true, "fill": RAIL, "margin": Vector2(0, 0)},
	"slot": {"band": 1.5, "radius": 2.0, "recessed": true, "fill": SLOT, "margin": Vector2(5, 4)},
	"slot_hover": {"band": 1.5, "radius": 2.0, "recessed": true, "fill": SLOT, "lit": true, "margin": Vector2(5, 4)},
	"slot_selected": {"band": 2.0, "radius": 2.0, "recessed": true, "fill": SLOT_SELECTED, "glow": true, "margin": Vector2(5, 4)},
	"button": {"band": 2.0, "radius": 3.0, "fill": BUTTON, "margin": Vector2(10, 6)},
	"button_hover": {"band": 2.0, "radius": 3.0, "fill": BUTTON_HOVER, "lit": true, "margin": Vector2(10, 6)},
	"button_pressed": {"band": 2.0, "radius": 3.0, "fill": SLOT_SELECTED, "glow": true, "margin": Vector2(10, 6)},
	"bar": {"band": 1.0, "radius": 2.0, "recessed": true, "fill": BAR_BACK, "margin": Vector2(1, 1)},
}


## A frame of this kind: "panel" (menus), "plate" (small HUD panels), "title" (the title screen),
## "action_bar", "slot", "slot_hover", "slot_selected", "button", "button_hover",
## "button_pressed", "badge" (a key in the controls row) or "bar" (behind a meter)
static func frame(kind: String) -> StyleBox:
	if kind in ["panel", "plate", "title"]:
		var art := _art_frame(kind)
		if art:
			return art
	if kind == "badge":
		var badge := StyleBoxFlat.new()
		badge.bg_color = BADGE_FILL
		badge.border_color = BRASS
		badge.set_border_width_all(1)
		badge.set_corner_radius_all(3)
		badge.content_margin_left = 6
		badge.content_margin_right = 6
		badge.content_margin_top = 1
		badge.content_margin_bottom = 1
		return badge
	var spec: Dictionary = KINDS.get(kind, KINDS["panel"])
	var margin: Vector2 = spec["margin"]
	var style := BrassFrame.new()
	style.fill = spec["fill"]
	style.band = spec["band"]
	style.radius = spec["radius"]
	style.rivets = spec.get("rivets", false)
	style.vignette = spec.get("vignette", false)
	style.recessed = spec.get("recessed", false)
	style.lit = spec.get("lit", false)
	style.glow = spec.get("glow", false)
	style.content_margin_left = margin.x
	style.content_margin_right = margin.x
	style.content_margin_top = margin.y
	style.content_margin_bottom = margin.y
	return style


# The plaque (menus and small panels) or the ornate frame (the title screen) as a scaled 9-slice,
# or null if that art isn't there
static func _art_frame(kind: String) -> StyleBox:
	var title := kind == "title"
	var art := texture("panel_frame" if title else "plaque")
	if art == null:
		return null
	var framed := ArtFrame.new()
	framed.texture = art
	framed.slice = TITLE_SLICE if title else PLAQUE_SLICE
	framed.scale = TITLE_FRAME_SCALE if title else (MENU_FRAME_SCALE if kind == "panel" else SMALL_FRAME_SCALE)
	var inside: Vector2 = (TITLE_INSIDE if title else PLAQUE_INSIDE) * framed.scale
	# Breathing room inside the frame's rim (the ornate frame's rim is deeper)
	var pad := Vector2(26, 20) if title else Vector2(10, 8)
	framed.content_margin_left = inside.x + pad.x
	framed.content_margin_right = inside.x + pad.x
	framed.content_margin_top = inside.y + pad.y
	framed.content_margin_bottom = inside.y + pad.y
	return framed


## A coloured fill for a bar (from bar_fill_<name>.png if there is one)
static func bar_fill(name: String, color: Color) -> StyleBox:
	var art := texture("bar_fill_" + name)
	if art:
		var sliced := StyleBoxTexture.new()
		sliced.texture = art
		sliced.set_texture_margin_all(4)
		return sliced
	var flat := StyleBoxFlat.new()
	flat.bg_color = color
	flat.set_corner_radius_all(2)
	# A lighter top edge, so it reads as a lit tube
	flat.border_width_top = 1
	flat.border_color = color.lightened(0.3)
	return flat


## Makes a frame look under the mouse (lit) or not
static func set_lit(style: StyleBox, on: bool) -> void:
	if style is BrassFrame:
		style.lit = on


## A texture from res://assets/ui/ (name without ".png"), or null if there's no such file yet.
## Keep the texture in a variable for as long as anything draws it: a draw call doesn't keep it
## loaded, and a texture that's been let go of draws as a blank white shape.
static func texture(name: String) -> Texture2D:
	var path := UI_FOLDER + name + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


## The button and tab look for a menu, set on a Button as overrides
static func style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", frame("button"))
	button.add_theme_stylebox_override("hover", frame("button_hover"))
	button.add_theme_stylebox_override("pressed", frame("button_pressed"))
	button.add_theme_stylebox_override("hover_pressed", frame("button_pressed"))
	button.add_theme_stylebox_override("disabled", frame("button"))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, TEXT)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.3))


## The faint gear for an empty inventory or chest slot, centred in `rect`
static func draw_slot_gear(canvas: CanvasItem, rect: Rect2) -> void:
	draw_gear(canvas, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.3, Color(BRASS.r, BRASS.g, BRASS.b, GEAR_ALPHA), 10)


## The text font for dials (the project's default)
static func font() -> Font:
	return ThemeDB.fallback_font


## A gear: `teeth` square teeth round a ring, with a hole in the middle, drawn on a CanvasItem
static func draw_gear(canvas: CanvasItem, center: Vector2, radius: float, color: Color, teeth := 10) -> void:
	var outline := PackedVector2Array()
	var inner := radius * 0.78
	for i in teeth:
		var a := TAU * i / teeth
		var w := TAU / teeth
		outline.append(center + Vector2.from_angle(a - w * 0.25) * inner)
		outline.append(center + Vector2.from_angle(a - w * 0.18) * radius)
		outline.append(center + Vector2.from_angle(a + w * 0.18) * radius)
		outline.append(center + Vector2.from_angle(a + w * 0.25) * inner)
	canvas.draw_colored_polygon(outline, color)
	# The hub: a ring with a hole, and spokes
	canvas.draw_arc(center, inner * 0.62, 0.0, TAU, 24, color.darkened(0.5), inner * 0.18)
	for i in 4:
		var d := Vector2.from_angle(PI / 4.0 + i * PI / 2.0)
		canvas.draw_line(center + d * inner * 0.3, center + d * inner * 0.75, color.darkened(0.45), maxf(radius * 0.08, 1.0))
	canvas.draw_circle(center, inner * 0.24, color.darkened(0.6))
