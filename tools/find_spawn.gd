extends SceneTree
## Grid-probes a visual-only map (baked on the fly by scripts/map_collision.gd) for a spawn point.
## A good spawn is: flat ground at street level, open for 2.4 m above it, and boxed in by geometry
## within swing range on several sides — a street canyon, not a rooftop and not inside a wall.
## Prints candidates in the map's OWN coordinates; offset the map by -spawn to put it at the origin.
## Usage: godot --headless -s tools/find_spawn.gd -- res://assets/maps/scene.gltf [grid]

const HEAD_CLEAR := 2.4     # m, free space needed above the ground point
const SWING_REACH := 40.0   # m, how far a building may be and still be a swing anchor
const MIN_SIDE := 3.0       # m, closer hits are street furniture, not a building to swing from
const PROBE_Y := 1.5        # m, chest height for the side probes

var _map: Node3D
var _frames := 0
var _grid := 10.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://assets/maps/scene.gltf"
	if args.size() > 1:
		_grid = float(args[1])
	_map = (load(path) as PackedScene).instantiate() as Node3D
	_map.set_script(load("res://scripts/map_collision.gd"))  # bakes on _ready
	get_root().add_child(_map)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false  # let the physics space register the freshly baked bodies
	_probe()
	return true


func _probe() -> void:
	var space := get_root().world_3d.direct_space_state
	var bounds := AABB()
	var first := true
	for mi in _meshes(_map):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	print("map bounds: min %s  max %s  size %s" % [bounds.position, bounds.end, bounds.size])

	# 1. Ground height at every grid point, and the modal value = street level.
	var grounds := {}
	var heights: Array[float] = []
	var x := bounds.position.x
	while x < bounds.end.x:
		var z := bounds.position.z
		while z < bounds.end.z:
			var hit := _down(space, x, z, bounds)
			if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.85:
				grounds[Vector2i(int(round(x)), int(round(z)))] = hit["position"]
				heights.append((hit["position"] as Vector3).y)
			z += _grid
		x += _grid
	if heights.is_empty():
		print("no ground found")
		return
	heights.sort()
	var modal := _modal(heights)
	print("ground samples: %d  street level (modal): %.2f m  min %.2f  max %.2f" % [
		heights.size(), modal, heights[0], heights[heights.size() - 1]])

	# 2. Score street-level points by clearance above and buildings around.
	var centre := bounds.get_center()
	var cands: Array = []
	for key in grounds:
		var p: Vector3 = grounds[key]
		if absf(p.y - modal) > 0.6:
			continue
		if not _clear(space, p):
			continue
		var sides := _sides(space, p)
		if sides < 3:
			continue
		var d := Vector2(p.x - centre.x, p.z - centre.z).length()
		cands.append([sides * 10.0 - d * 0.02, sides, p])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	print("--- top candidates (map space) ---")
	for i in mini(cands.size(), 12):
		var c: Array = cands[i]
		print("  %2d) pos %s  sides %d  score %.1f" % [i + 1, c[2], c[1], c[0]])
	if not cands.is_empty():
		_detail(space, cands[0][2])


## Street profile at the chosen point. The number that matters: how many faces a horizontal ray
## reaches are vertical with an outward normal — those are the ones wall.gd can actually grab.
func _detail(space: PhysicsDirectSpaceState3D, p: Vector3) -> void:
	print("--- detail for best candidate %s ---" % p)
	var from := p + Vector3.UP * PROBE_Y
	var tot := 0
	var vert := 0
	var usable := 0
	var dists: Array[float] = []
	for i in 24:
		var a := TAU * float(i) / 24.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var d: float = from.distance_to(hit["position"])
		if d < MIN_SIDE:
			continue
		var n: Vector3 = hit["normal"]
		tot += 1
		dists.append(d)
		var facing := n.dot(-dir)
		if absf(n.y) < 0.35:
			vert += 1
			if facing > 0.0:
				usable += 1
			var c = hit["collider"]
			var owner_name := "?"
			if c is Node and c.get_parent() is Node:
				owner_name = str(c.get_parent().name)
			print("  %3d deg  d=%6.1f  y=%6.1f  facing=%+.2f  '%s'" % [
				int(rad_to_deg(a)), d, hit["position"].y, facing, owner_name])
	dists.sort()
	if tot == 0:
		print("  no faces within 120 m")
		return
	print("  faces within 120 m: %d   distance min %.1f / median %.1f / max %.1f m" % [
		tot, dists[0], dists[tot / 2], dists[tot - 1]])
	print("  vertical faces: %d/%d (%.0f%%)   wall-attachable (vertical + outward normal): %d/%d (%.0f%%)" % [
		vert, tot, 100.0 * vert / tot, usable, tot, 100.0 * usable / tot])


func _down(space: PhysicsDirectSpaceState3D, x: float, z: float, b: AABB) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, b.end.y + 50.0, z), Vector3(x, b.position.y - 20.0, z))
	return space.intersect_ray(q)


## Free space for the player's capsule at this point: a 0.6 m sphere at chest height plus 2.4 m
## of headroom. A single vertical ray is not enough — it happily passes inside a parked car.
func _clear(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var sh := SphereShape3D.new()
	sh.radius = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), p + Vector3.UP * 0.9)
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var up := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.25, p + Vector3.UP * HEAD_CLEAR)
	return space.intersect_ray(up).is_empty()


## How many of 8 compass directions see geometry within swing reach (a street canyon scores high).
## Hits closer than MIN_SIDE are ignored: that is a parked car or a kerb, not a building.
func _sides(space: PhysicsDirectSpaceState3D, p: Vector3) -> int:
	var from := p + Vector3.UP * PROBE_Y
	var n := 0
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * SWING_REACH)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and from.distance_to(hit["position"]) > MIN_SIDE:
			n += 1
	return n


func _modal(sorted_heights: Array[float]) -> float:
	var best_bin := 0
	var best_count := 0
	var i := 0
	while i < sorted_heights.size():
		var lo := sorted_heights[i]
		var j := i
		while j < sorted_heights.size() and sorted_heights[j] < lo + 1.0:
			j += 1
		if j - i > best_count:
			best_count = j - i
			best_bin = i
		i = j
	return sorted_heights[best_bin]


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			out.append(c)
		out.append_array(_meshes(c))
	return out