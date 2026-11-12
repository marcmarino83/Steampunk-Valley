extends Control
## The parchment page that notes, journals and logs are read on.
## The player owns one of these; anything readable calls player.read_note() to open it.

@onready var title_label: Label = $Center/Paper/VBox/Title
@onready var body_label: Label = $Center/Paper/VBox/Body


func _ready() -> void:
	# In-world text: the page's title and words in the in-world font (see BrassStyle's fonts)
	title_label.add_theme_font_override("font", BrassStyle.inworld_font())
	body_label.add_theme_font_override("font", BrassStyle.inworld_font())
	$Center/Paper/VBox/Hint.add_theme_font_override("font", BrassStyle.inworld_italic_font())
	MenuStyle.enlarge($Center/Paper)


func open(title: String, text: String) -> void:
	title_label.text = title
	body_label.text = text
	show()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible
