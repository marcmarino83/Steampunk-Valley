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
##   vitals_panel.png  the hunger and stamina panel with its gauge (see VitalsPanel)
##   crosshair.png     drawn at 32 px (see HudInstruments)

const UI_FOLDER := "res://assets/ui/"

# ---- The palette: every interface colour comes from here (DESIGN.md, Interface style) ----
## Text: body text, quieter text (labels, subtitles, notes), and brass headings (panel titles,
## section headings, the menus' titles)
const TEXT := Color(0.94, 0.86, 0.68)
const TEXT_DIM := Color(0.72, 0.64, 0.5)
const HEADING := Color(0.94, 0.8, 0.55)
## Status: good (working, fed, done), warning (clear yellow: missing something, worth a look),
## error (can't, failed, dangerous), neutral (idle, nothing to say), and info (in progress,
## visiting, permanent). Never orange (see CLAUDE.md).
const GOOD := Color(0.62, 0.9, 0.5)
const WARN := Color(1.0, 0.92, 0.35)
const BAD := Color(1.0, 0.4, 0.33)
const NEUTRAL := TEXT_DIM
const INFO := Color(0.6, 0.8, 1.0)
## Plain white, for neutral highlights (a selected tag, a footprint line)
const HIGHLIGHT := Color(1.0, 1.0, 1.0)

# ---- Type sizes and spacing (in the menus' 1152 × 648 layout; menus are drawn MENU_SCALE bigger) ----
const SIZE_HEADER := 24
const SIZE_SECTION := 14
const SIZE_BODY := 15
const SIZE_SMALL := 13
const SIZE_HINT := 12
## The spacing steps: within a row, between rows, between sections, around groups
const GAP_XS := 4
const GAP_S := 8
const GAP_M := 12
const GAP_L := 18
## Button heights: standard, and small (inline in a row, like Unassign)
const BUTTON_H := 30
const BUTTON_SMALL_H := 24
const BUTTON_MIN_W := 96
## How long a danger button waits for its second click (seconds)
const CONFIRM_SECONDS := 3.0
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
## Stamina: a pale electric blue-green, clear of the hunger gold
const STAMINA_FILL := Color(0.36, 0.78, 0.82)
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


## The slider look: a dark recessed track with a brass fill up to the grabber (brighter while
## hovered or focused)
static func style_slider(slider: Slider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = BAR_BACK
	track.border_color = BRASS_DARK
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = BRASS
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var lit := fill.duplicate() as StyleBoxFlat
	lit.bg_color = BRASS_LIGHT
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", lit)


## The faint gear for an empty inventory or chest slot, centred in `rect`
static func draw_slot_gear(canvas: CanvasItem, rect: Rect2) -> void:
	draw_gear(canvas, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.3, Color(BRASS.r, BRASS.g, BRASS.b, GEAR_ALPHA), 10)


## The text font for dials (the project's default)
static func font() -> Font:
	return ThemeDB.fallback_font


# ---- The standard pieces every panel is built from (see BrassPanel) ----

## A label in one of the type sizes and palette colours
static func label(text: String, size := SIZE_BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A button of a kind: "primary" (the panel's main action, lighter brass; one per panel),
## "secondary" (the rest), "danger" (red text; give it a confirm with arm_confirm) or "small"
## (inline in a row, like Unassign). Sized to its text, never narrower than BUTTON_MIN_W.
static func button(text: String, kind := "secondary") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	style_button(b)
	var small := kind == "small"
	b.custom_minimum_size = Vector2(0 if small else BUTTON_MIN_W, BUTTON_SMALL_H if small else BUTTON_H)
	b.add_theme_font_size_override("font_size", SIZE_SMALL if small else SIZE_BODY)
	if kind == "primary":
		for state in ["normal", "hover"]:
			var lit: StyleBox = frame("button_hover" if state == "hover" else "button")
			if lit is BrassFrame:
				(lit as BrassFrame).fill = PRIMARY if state == "normal" else PRIMARY_HOVER
			b.add_theme_stylebox_override(state, lit)
	elif kind == "danger":
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(state, BAD)
	return b


## A primary button's brass fill, and under the mouse
const PRIMARY := Color(0.42, 0.3, 0.15)
const PRIMARY_HOVER := Color(0.5, 0.36, 0.18)


## A danger button's confirm: the first click arms it ("Click again to remove", for
## CONFIRM_SECONDS), the second does `action`. Use instead of connecting `pressed`.
static func arm_confirm(b: Button, action: Callable, again_text := "") -> void:
	var resting := b.text
	var armed := again_text if not again_text.is_empty() else "Click again to %s" % resting.to_lower()
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = CONFIRM_SECONDS
	b.add_child(timer)
	b.set_meta(&"confirm_timer", timer)
	b.set_meta(&"confirm_text", resting)
	timer.timeout.connect(func(): b.text = resting)
	b.pressed.connect(func():
		if timer.is_stopped():
			b.text = armed
			timer.start()
		else:
			timer.stop()
			b.text = resting
			action.call())


## Puts an armed danger button back to waiting for its first click (a panel opening again)
static func disarm(b: Button) -> void:
	if b.has_meta(&"confirm_timer"):
		(b.get_meta(&"confirm_timer") as Timer).stop()
		b.text = b.get_meta(&"confirm_text")


## Disables a button and says why: in its tooltip, and with `in_label`, as its text (the reason
## then replaces the label, like "Needs a free home"); enabled again with an empty reason
static func set_disabled_reason(b: Button, reason: String, label_text := "", in_label := false) -> void:
	b.disabled = not reason.is_empty()
	b.tooltip_text = reason
	if not label_text.is_empty():
		b.text = reason if in_label and not reason.is_empty() else label_text


## A status pill: a small rounded tag in a status colour ("● Working")
static func pill(text: String, color := GOOD) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(label("", SIZE_SMALL, color))
	set_pill(p, text, color)
	return p


static func set_pill(p: PanelContainer, text: String, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.14)
	style.border_color = Color(color, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", style)
	var l := p.get_child(0) as Label
	l.text = "● " + text
	l.add_theme_color_override("font_color", color)
	p.visible = not text.is_empty()


## The key-hint row: each [key, what it does] as a small key badge and a word or two
## ("M Move · P Plot view · E Close"). Never paragraphs: longer explanations go in tooltips.
static func hint_row(pairs := []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP_M)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	set_hints(row, pairs)
	return row


static func set_hints(row: HBoxContainer, pairs: Array) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for p in pairs:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", GAP_XS)
		var key := label(p[0], SIZE_HINT, BRASS_LIGHT)
		key.add_theme_stylebox_override("normal", frame("badge"))
		pair.add_child(key)
		pair.add_child(label(p[1], SIZE_HINT, TEXT_DIM))
		row.add_child(pair)
	row.visible = not pairs.is_empty()


## A thin brass line between a panel's parts
static func divider() -> HSeparator:
	var line := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Color(BRASS_DARK, 0.55)
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	return line


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
