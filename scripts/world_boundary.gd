extends Node3D
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
const BoundarySign := preload("res://scripts/boundary_sign.gd")
## Perimeter barrier that follows the map's real edge, plus a floor under it.
## Walls come from assets/maps/footprint.json (tools/trace_footprint.gd): one rect per straight run
## of exterior-facing edge, so they hug the buildings and roads instead of a bounding box.
## Solid for the player on Layers.BOUNDARY, which every gameplay ray masks out, so a web or zip
## never anchors to the barrier.
## Each wall run carries "Do Not Enter" panels on its playable face, one per STEP metres of
## perimeter walked, faded in by distance (scripts/boundary_sign.gd).
## ponytail: no ceiling, dev fly is noclip so a lid would only cause an invisible head-bonk.

const FOOTPRINT := "res://assets/maps/footprint.json"
const WALL_TOP := 600.0    # m absolute: far above the tallest roof, any swing or super jump
const STEP := 40.0         # m of perimeter between signs
const SIGN_CENTRE_Y := 2.2  # m above street level
const SIGN_WIDTH := 3.2     # m along the wall
const SIGN_HEIGHT := 1.7    # m up the wall
const SIGN_OFFSET := 0.06   # m, panel stands just proud of the wall face

var _signs: Array = []


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOOTPRINT))
	if data == null:
		push_warning("WorldBoundary: %s missing — run tools/trace_footprint.gd" % FOOTPRINT)
		return
	var top := maxf(float(data["top"]), WALL_TOP)
	var bottom := float(data["bottom"])
	var walls: Array = data["walls"]

	var acc := 0.0
	for w in walls:
		var lo := Vector2(float(w["min"][0]), float(w["min"][1]))
		var hi := Vector2(float(w["max"][0]), float(w["max"][1]))
		var inward := Vector2(float(w["in"][0]), float(w["in"][1]))
		_wall(lo, hi, bottom, top)
		acc += maxf(hi.x - lo.x, hi.y - lo.y)
		if acc >= STEP:
			acc = 0.0
			_place_sign(lo, hi, inward, bottom)

	# Floor under the whole playable area, so a fall lands here instead of falling forever.
	var origin := Vector2(float(data["origin"][0]), float(data["origin"][1]))
	var span := Vector2(float(data["grid"][0]), float(data["grid"][1])) * float(data["cell"])
	_box(Vector3(origin.x + span.x * 0.5, bottom - 1.0, origin.y + span.y * 0.5),
		Vector3(span.x + 8.0, 2.0, span.y + 8.0))
	print("[MAP] boundary: %d wall runs, %d signs, floor %.0f x %.0f m" % [
		walls.size(), _signs.size(), span.x, span.y])


func _wall(lo: Vector2, hi: Vector2, bottom: float, top: float) -> void:
	var sz := hi - lo
	_box(Vector3((lo.x + hi.x) * 0.5, (bottom + top) * 0.5, (lo.y + hi.y) * 0.5),
		Vector3(sz.x, top - bottom, sz.y))


## One panel at the centre of this run's playable face, turned to look at the playable side.
func _place_sign(lo: Vector2, hi: Vector2, inward: Vector2, bottom: float) -> void:
	var along_x := absf(hi.x - lo.x) > absf(hi.y - lo.y)
	var face := Vector3((lo.x + hi.x) * 0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, (lo.y + hi.y) * 0.5)
	# The playable face is the wall side that `inward` points to. The footprint's `in` is the
	# direction from the wall toward play, so the face is the box edge on that side.
	if along_x:
		face.z = hi.y if inward.y > 0.0 else lo.y
	else:
		face.x = hi.x if inward.x > 0.0 else lo.x
	var s := BoundarySign.new()
	s.name = "DoNotEnter%d" % _signs.size()
	s.size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	s.position = face + Vector3(inward.x, 0.0, inward.y) * SIGN_OFFSET
	s.position.y = bottom + 2.0 + SIGN_CENTRE_Y
	s.rotation.y = atan2(inward.x, inward.y)  # a quad looks down its local +Z
	add_child(s)
	_signs.append(s)


func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = Layers.BOUNDARY
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
