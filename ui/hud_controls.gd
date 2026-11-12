class_name HudControls
extends Control
## The compact on-screen controls, Valheim-style:
##   - a centred row just above the action bar of what you can do right now, each as a label and
##     a key in a small dark box ("Place [LMB]  Rotate [R] ...");
##   - above that, while placing or demolishing, a small panel with the piece's icon, name and
##     cost (or refund), and one short line of details;
##   - a small line just below the crosshair for what E (and F) would do.
## The player tells it what to show each frame; it only rebuilds what changed.

const TEXT := BrassStyle.TEXT
const DETAIL := BrassStyle.TEXT_DIM
const BAD := BrassStyle.BAD
## A warning that doesn't stop placing (steep ground)
const WARN := BrassStyle.WARN
const KEY_TEXT := BrassStyle.BRASS_LIGHT
const LABEL_SIZE := 16
const KEY_SIZE := 14
## Gaps, in pixels at 1920 × 1080: above the action bar, between the panel and the row, and
## from the crosshair down to the prompt line
const ABOVE_BAR := 10.0
const PANEL_GAP := 8.0
const BELOW_CROSSHAIR := 26.0

var _row: HBoxContainer
var _prompts: HBoxContainer
var _panel: PanelContainer
var _icon: TextureRect
var _title: Label
var _cost: Label
var _detail: Label
# What's showing, so nothing is rebuilt unless it changed
var _shown_controls: Array = []
var _shown_prompts: Array = []
var _bar_top := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = _pairs_row()
	add_child(_row)
	_prompts = _pairs_row()
	add_child(_prompts)
	_build_panel()


## The controls row: [[label, key], ...]. Empty hides it.
func set_controls(pairs: Array) -> void:
	if pairs == _shown_controls:
		return
	_shown_controls = pairs.duplicate(true)
	_fill(_row, pairs)


## The line under the crosshair: [[key, what it does], ...], key first ("[E] Pick up Stone")
func set_prompts(pairs: Array) -> void:
	if pairs == _shown_prompts:
		return
	_shown_prompts = pairs.duplicate(true)
	_fill(_prompts, pairs, true)


## The piece panel: {"icon", "title", "cost", "cost_bad", "detail", "detail_bad"}; empty hides it
func set_info(info: Dictionary) -> void:
	_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	_icon.texture = info.get("icon")
	_icon.visible = _icon.texture != null
	_title.text = info.get("title", "")
	_cost.text = info.get("cost", "")
	_cost.visible = not _cost.text.is_empty()
	_cost.add_theme_color_override("font_color", BAD if info.get("cost_bad", false) else TEXT)
	_detail.text = info.get("detail", "")
	_detail.visible = not _detail.text.is_empty()
	_detail.add_theme_color_override("font_color", BAD if info.get("detail_bad", false) else (WARN if info.get("detail_warn", false) else DETAIL))


## Where the top of the action bar is on screen, so the row sits just above it
func set_bar_top(y: float) -> void:
	_bar_top = y


## Where the controls row is on screen (empty while it's hidden), so the compass can keep clear
## of it
func row_rect() -> Rect2:
	return _row.get_global_rect() if _row.visible and not _shown_controls.is_empty() else Rect2()


func _process(_delta: float) -> void:
	var screen := get_viewport_rect().size
	_row.size = _row.get_combined_minimum_size()
	_row.position = Vector2((screen.x - _row.size.x) / 2.0, _bar_top - ABOVE_BAR - _row.size.y)
	var row_top := _row.position.y if _row.visible else _bar_top - ABOVE_BAR
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = Vector2((screen.x - _panel.size.x) / 2.0, row_top - PANEL_GAP - _panel.size.y)
	_prompts.size = _prompts.get_combined_minimum_size()
	_prompts.position = Vector2((screen.x - _prompts.size.x) / 2.0, screen.y / 2.0 + BELOW_CROSSHAIR)


func _pairs_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	row.visible = false
	return row


# Fills a row with label + key pairs (or key + label, for prompts)
func _fill(row: HBoxContainer, pairs: Array, key_first := false) -> void:
	for child in row.get_children():
		child.queue_free()
	row.visible = not pairs.is_empty()
	for pair in pairs:
		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 5)
		var words := _label(pair[1] if key_first else pair[0], LABEL_SIZE, TEXT)
		var key := _key_badge(pair[0] if key_first else pair[1])
		if key_first:
			item.add_child(key)
			item.add_child(words)
		else:
			item.add_child(words)
			item.add_child(key)
		row.add_child(item)


# A key in a small dark rounded box
func _key_badge(text: String) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", BrassStyle.frame("badge"))
	var label := _label(text, KEY_SIZE, KEY_TEXT)
	label.add_theme_constant_override("outline_size", 0)
	badge.add_child(label)
	return badge


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BrassStyle.frame("plate")
	_panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	_panel.add_child(line)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_icon)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 10)
	words.add_child(top)
	_title = _label("", 17, TEXT)
	top.add_child(_title)
	_cost = _label("", 15, TEXT)
	top.add_child(_cost)
	_detail = _label("", 13, DETAIL)
	words.add_child(_detail)
	_panel.visible = false
	add_child(_panel)
