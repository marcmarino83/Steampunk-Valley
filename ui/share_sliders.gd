class_name ShareSliders
extends VBoxContainer
## The sliders that share a plot's output out between its items (the Forager's Hut): one row per
## item (its name, a slider, and how many a day). Moving one sets the plot's own value
## (Plot.set_share) and the others follow, so the total stays 100%. The plot panel and the Village
## screen's Resources tab both show these for the same plot, and both write the one value the plot
## keeps: call sync() when it may have changed elsewhere.

## A slider moved (the plot's shares have changed)
signal changed

var plot: Plot
## item -> its HSlider
var sliders := {}
var _amounts := {}
# The item whose slider is being dragged (its percentage shows beside it while it is)
var _dragging := ""


## Sliders for this plot's shared output (its items in their order)
static func create(for_plot: Plot, label_width := 92.0) -> ShareSliders:
	var s := ShareSliders.new()
	s.plot = for_plot
	s.add_theme_constant_override("separation", BrassStyle.GAP_XS)
	for item in for_plot.shares():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", BrassStyle.GAP_S)
		var item_label := BrassStyle.label(item, BrassStyle.SIZE_BODY, BrassStyle.TEXT)
		item_label.custom_minimum_size.x = label_width
		row.add_child(item_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y = 18
		slider.focus_mode = Control.FOCUS_NONE
		BrassStyle.style_slider(slider)
		slider.value_changed.connect(s._on_moved.bind(item))
		slider.drag_started.connect(func():
			s._dragging = item
			s.sync())
		slider.drag_ended.connect(func(_moved):
			s._dragging = ""
			s.sync())
		row.add_child(slider)
		var amount := BrassStyle.label("", BrassStyle.SIZE_SMALL, BrassStyle.TEXT_DIM)
		amount.custom_minimum_size.x = 84
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		s.add_child(row)
		s.sliders[item] = slider
		s._amounts[item] = amount
	s.sync()
	return s


## Shows the plot's current shares and amounts a day (without sending `changed`)
func sync() -> void:
	if plot == null or not is_instance_valid(plot):
		return
	var shares := plot.shares()
	var made := plot.daily_output()
	for item in sliders:
		(sliders[item] as HSlider).set_value_no_signal(int(shares.get(item, 0)))
		var per_day := "%d/day" % int(made.get(item, 0))
		(_amounts[item] as Label).text = ("%d%%  ·  %s" % [int(shares.get(item, 0)), per_day]) if item == _dragging else per_day


func _on_moved(value: float, item: String) -> void:
	plot.set_share(item, roundi(value))
	sync()
	changed.emit()
