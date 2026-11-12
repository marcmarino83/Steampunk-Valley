class_name PreviewLook
## How the thing being placed shows its placement state, the way Valheim does: the preview wears the
## piece's real look (its own materials, colour and close-up detail, solid), and over it a light tint
## and a thin outline: a soft white glow where it can go, yellow where it can go with a warning, red
## where it can't (never orange: see CLAUDE.md). Both are drawn as each mesh's overlay (GeometryInstance3D.material_overlay:
## the tint, preview_tint.gdshader, with the outline, preview_outline.gdshader, as its next pass), so
## the real materials underneath are never touched. Used by the building-piece placer
## (ValheimPlacer) and the workbench, chest and campfire placer (BuildPlacer); template ghosts use the
## outline alone for the one under the crosshair (see BuildPiece.set_ghost_targeted).

enum State { VALID, WARN, INVALID, GHOST_TARGET, GHOST_FADE }

const TINT_SHADER := preload("res://building/preview_tint.gdshader")
const OUTLINE_SHADER := preload("res://building/preview_outline.gdshader")
## Per state: [tint (colour, strength), edge glow, outline colour, outline width in pixels]
const LOOKS := {
	# (a soft white glow and a thin white outline: the real wood stays clearly visible; never orange)
	State.VALID: [Color(1.0, 1.0, 1.0, 0.07), Color(1.0, 1.0, 1.0, 0.3), Color(1.0, 1.0, 1.0), 1.5],
	# (a clear yellow, not gold)
	State.WARN: [Color(BrassStyle.WARN, 0.16), Color(BrassStyle.WARN, 0.4), BrassStyle.WARN, 1.75],
	State.INVALID: [Color(1.0, 0.16, 0.1, 0.3), Color(1.0, 0.3, 0.24, 0.55), Color(1.0, 0.18, 0.12), 2.0],
	# (a template ghost under the crosshair: no tint, a light cool outline)
	State.GHOST_TARGET: [Color(0.85, 0.9, 1.0, 0.0), Color(0.85, 0.9, 1.0, 0.25), Color(0.86, 0.9, 1.0), 1.5],
	# (a template ghost wearing a model's own materials, which can't fade themselves the way the
	# pieces' shaders do (their ghost_fade): faded and drained toward a pale cool grey, no outline)
	State.GHOST_FADE: [Color(0.62, 0.65, 0.7, 0.55), Color(0.7, 0.73, 0.78, 0.65), Color(), 0.0],
}

static var _materials := {}


## The overlay for a state (shared: made once)
static func overlay(state: int) -> ShaderMaterial:
	if not _materials.has(state):
		var look: Array = LOOKS[state]
		var tint := ShaderMaterial.new()
		tint.shader = TINT_SHADER
		tint.set_shader_parameter("tint", look[0])
		tint.set_shader_parameter("rim_color", look[1])
		if float(look[3]) > 0.0:
			var outline := ShaderMaterial.new()
			outline.shader = OUTLINE_SHADER
			outline.set_shader_parameter("color", look[2])
			outline.set_shader_parameter("width_px", look[3])
			tint.next_pass = outline
		_materials[state] = tint
	return _materials[state]


## Gives every mesh under `root` the state's overlay (or none, with `clear`)
static func apply(root: Node, state: int, clear := false) -> void:
	if root is GeometryInstance3D and not root is GPUParticles3D:
		wear(root, state, clear)
	for look in root.find_children("*", "GeometryInstance3D", true, false):
		if look is GPUParticles3D:
			continue
		wear(look, state, clear)


## Gives one mesh the state's overlay (or none, with `clear`), telling the outline where its middle is
static func wear(look: GeometryInstance3D, state: int, clear := false) -> void:
	look.material_overlay = null if clear else overlay(state)
	if not clear and float(LOOKS[state][3]) > 0.0:
		look.set_instance_shader_parameter("outline_center", look.get_aabb().get_center())


## Lets go of the shared overlays (when the world closes, so nothing is reported leaked)
static func clear_cache() -> void:
	_materials.clear()
