class_name ArtFrame
extends StyleBox
## A frame drawn from a texture as a 9-slice: the corners kept as drawn and the edges and middle
## stretched, all shrunk or grown by `scale`, so one detailed texture suits big menus and small
## panels alike. (Godot's own StyleBoxTexture always draws its corners at the texture's pixel
## size, which is why this exists.)

var texture: Texture2D
## The 9-slice margins in the texture's pixels: left, top, right, bottom
var slice := Vector4(0, 0, 0, 0)
## How big the texture's pixels are drawn (0.25 = a quarter size)
var scale := 1.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	# Drawn in the texture's own pixels, shrunk to `scale` about the rect's corner
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, Vector2(scale, scale), 0.0, rect.position))
	RenderingServer.canvas_item_add_nine_patch(to_canvas_item, Rect2(Vector2.ZERO, rect.size / scale), Rect2(Vector2.ZERO, texture.get_size()), texture.get_rid(),
			Vector2(slice.x, slice.y), Vector2(slice.z, slice.w), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true)
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D.IDENTITY)
