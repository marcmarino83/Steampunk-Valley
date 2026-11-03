extends StaticBody3D
## Something you can read: a note, journal, log, letter or sign.
## Give it a collision shape and a mesh, set the title and text, and it just works:
## looking at it shows "[E] Read <title>", and pressing E opens it on a parchment panel.

## Shown on the prompt ("[E] Read Ship's Log") and as the heading on the page
@export var title := "Note"
## What's written on it. Leave a blank line between paragraphs.
@export_multiline var text := ""
## The word on the prompt, e.g. "Read", "Examine", "Study"
@export var verb := "Read"


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "%s %s" % [verb, title]


func interact(player) -> void:
	player.read_note(title, text)
