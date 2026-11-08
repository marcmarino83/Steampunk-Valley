extends Control
## The parchment page that notes, journals and logs are read on.
## The player owns one of these; anything readable calls player.read_note() to open it.

@onready var title_label: Label = $Center/Paper/VBox/Title
@onready var body_label: Label = $Center/Paper/VBox/Body


func _ready() -> void:
	MenuStyle.enlarge($Center/Paper)


func open(title: String, text: String) -> void:
	title_label.text = title
	body_label.text = text
	show()


func close() -> void:
	hide()


func is_open() -> bool:
	return visible
