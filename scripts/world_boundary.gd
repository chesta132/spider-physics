extends Node3D
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
## Invisible shell around the map so the player cannot walk, fall or swing out of the playable
## world. Built from the map's own mesh bounds, so it follows the map if the map or its offset
## changes. Solid for the player body, on Layers.BOUNDARY, which every gameplay ray masks out:
## a web or zip must never anchor to the boundary, or swinging would grab thin air at the edge.
## ponytail: no ceiling — dev fly is noclip anyway, so a lid could only ever cause an invisible
## head-bonk. Add one if a flight mode ever stops being noclip.

const DROP := 30.0    # m the shell reaches below the map's lowest point, to catch a fall
const RISE := 30.0    # m above the map's highest point
const THICK := 4.0    # m wall thickness
const MARGIN := 2.0   # m of clearance outside the outermost geometry


func _ready() -> void:
	var b := _bounds()
	if b.size == Vector3.ZERO:
		push_warning("WorldBoundary: no map meshes found, no shell built")
		return
	b = b.grow(MARGIN)
	var lo := Vector3(b.position.x, b.position.y - DROP, b.position.z)
	var hi := Vector3(b.end.x, b.end.y + RISE, b.end.z)
	var mid := (lo + hi) * 0.5
	var s := hi - lo
	var e := THICK * 2.0  # overlap the corners so there is no gap at a diagonal
	_box(Vector3(lo.x - THICK * 0.5, mid.y, mid.z), Vector3(THICK, s.y, s.z + e))
	_box(Vector3(hi.x + THICK * 0.5, mid.y, mid.z), Vector3(THICK, s.y, s.z + e))
	_box(Vector3(mid.x, mid.y, lo.z - THICK * 0.5), Vector3(s.x + e, s.y, THICK))
	_box(Vector3(mid.x, mid.y, hi.z + THICK * 0.5), Vector3(s.x + e, s.y, THICK))
	_box(Vector3(mid.x, lo.y - THICK * 0.5, mid.z), Vector3(s.x + e, THICK, s.z + e))
	print("[MAP] boundary shell x %.0f..%.0f  z %.0f..%.0f  y %.0f..%.0f" % [
		lo.x, hi.x, lo.z, hi.z, lo.y, hi.y])


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


## Mesh bounds of the whole map, measured from the parent so the offset and import scale apply.
func _bounds() -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [get_parent()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in n.get_children():
			if c != self:
				stack.append(c)
	return out