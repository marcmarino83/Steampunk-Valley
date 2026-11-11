class_name TexturedWall
## TEST ONLY (see tests/texture_test.gd): Wall 2 m drawn with texture-based detail instead of
## modelled boards. The wall face is one solid slab; its board joints and grain come from the wood
## plank textures (mipmapped, so they fade smoothly with distance instead of breaking into dashes),
## mapped at real-world scale with the boards running level, as many to the metre as the modelled
## wall's (PieceDetail.BOARDS boards to a PieceDetail.TEX tile: 0.25 m boards). Real geometry is kept
## only where it changes the outline: the top and bottom rails here, and the corner post with its
## rope lashings where walls meet (JointDetails' post, PieceDetail.post_mesh).
##
## It's drawn with the same shared material as every piece's close-up look
## (PieceRegistry.detail_material: the wood family's one material), so each piece's own slight
## colour still comes from its instance tint (see BuildPiece.weather).
##
## Two looks:
##   - near: the slab with its rails (NEAR_RANGE)
##   - far: the slab alone (the rails are only 2 cm proud of it), beyond that
## No piece uses this yet: nothing in the build menu, saves or templates.

## The slab's thickness (its faces 1 cm inside the wall's 0.2 m collision, where the modelled
## planks' faces are), and the rails' (1 cm proud of the collision: trim)
const SLAB := 0.18
const RAIL_DEPTH := 0.22
const RAIL_HEIGHT := 0.12
## The near look shows within this distance (then the far one), each fading over FADE
const NEAR_RANGE := 30.0
const FADE := 2.0
## How many metres one copy of the plank texture covers (PieceDetail.TEX, holding PieceDetail.BOARDS
## boards)
const TILE := PieceDetail.TEX
## The vertex shades: the slab's boards, and the rails a little darker (as the modelled trim)
const SLAB_SHADE := Color(0.95, 0.95, 0.95)
const RAIL_SHADE := Color(0.8, 0.8, 0.8)


## The near look: the slab and its top and bottom rails
static func near_mesh(width := PieceShapes.GRID, height := PieceShapes.GRID_WALL_HEIGHT) -> ArrayMesh:
	var st := _surface()
	_box(st, Vector3(-width / 2.0, RAIL_HEIGHT, -SLAB / 2.0), Vector3(width / 2.0, height - RAIL_HEIGHT, SLAB / 2.0), SLAB_SHADE)
	_box(st, Vector3(-width / 2.0, 0.0, -RAIL_DEPTH / 2.0), Vector3(width / 2.0, RAIL_HEIGHT, RAIL_DEPTH / 2.0), RAIL_SHADE)
	_box(st, Vector3(-width / 2.0, height - RAIL_HEIGHT, -RAIL_DEPTH / 2.0), Vector3(width / 2.0, height, RAIL_DEPTH / 2.0), RAIL_SHADE)
	st.generate_tangents()
	return st.commit()


## The far look: the slab alone, the wall's full height
static func far_mesh(width := PieceShapes.GRID, height := PieceShapes.GRID_WALL_HEIGHT) -> ArrayMesh:
	var st := _surface()
	_box(st, Vector3(-width / 2.0, 0.0, -SLAB / 2.0), Vector3(width / 2.0, height, SLAB / 2.0), SLAB_SHADE)
	st.generate_tangents()
	return st.commit()


static func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# A box from `lo` to `hi`, every face mapped to the plank texture at real-world scale: on upright
# faces the texture turned so its boards run level (across the boards: up the wall; along them: along
# the face), on the top and bottom faces along X
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, shade: Color) -> void:
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [
		[[4, 5, 6, 7], Vector3.BACK], [[1, 0, 3, 2], Vector3.FORWARD],
		[[5, 1, 2, 6], Vector3.RIGHT], [[0, 4, 7, 3], Vector3.LEFT],
		[[7, 6, 2, 3], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN],
	]
	for f in faces:
		var idx: Array = f[0]
		var n: Vector3 = f[1]
		var q := idx.map(func(i): return c[i])
		_tri(st, q[0], q[1], q[2], n, shade)
		_tri(st, q[0], q[2], q[3], n, shade)


# One triangle, wound so its front faces along `n` (as PieceDetail._tri winds them), with its texture
# coordinates and the wood kind (UV2.x = 0: see piece_detail.gdshader)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, shade: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_color(shade)
		st.set_uv(_uv(p, n))
		st.set_uv2(Vector2(0.0, 0.0))
		st.add_vertex(p)


# Real-world texture coordinates: the texture's boards stand upright in it, so on an upright face
# its across-the-boards axis runs up the wall and its along-the-boards axis along the face
static func _uv(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.5:
		return Vector2(p.z, p.x) / TILE
	var along := p.x if absf(n.z) > 0.5 else p.z
	return Vector2(p.y, along) / TILE
