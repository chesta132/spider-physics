extends SceneTree
## Traces the map's playable footprint from its own collision, so the perimeter barrier hugs the real
## edge instead of a bounding box. A 2 m top-down grid: a cell is solid when a ray dropped through it
## hits WORLD geometry. The exterior is the empty region connected to the grid border. Every playable
## cell that touches the exterior contributes an edge; edges merge into straight runs, and each run
## becomes one wall rect lying on the exterior side of the edge.
## Writes assets/maps/footprint.json (the barrier reads it) and a colour preview PNG.
## Re-run only when the map changes. Run: godot --headless -s tools/trace_footprint.gd

const Layers := preload("res://scripts/layers.gd")
const CELL := 2.0          # m per grid cell
const MARGIN := 4.0        # m of empty ring around the map, so the exterior is always connected
const T := 2.0             # m, wall thickness: one cell
const INSET := 3.0         # m the barrier sits inside the map's outer edge
const TOP_PAD := 30.0      # m above the tallest geometry (world_boundary may raise the top further)
const BOTTOM := -2.0       # m, where the walls end, under the floor
const OUT_JSON := "res://assets/maps/footprint.json"
const OUT_PNG := "/home/chardy/.hermes/cache/scratch/footprint.png"

var _map: Node3D
var _frames := 0


func _initialize() -> void:
	_map = (load("res://scenes/map_city.tscn") as PackedScene).instantiate()
	root.add_child(_map)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false  # the baked bodies reach the physics space on the first physics step
	trace()
	return true


func trace() -> void:
	var t0 := Time.get_ticks_msec()
	# Map bounds from its meshes, skipping the barrier's own preview quads.
	var b := AABB()
	var first := true
	var stack: Array = [_map]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "WorldBoundary":
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m := (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			b = m if first else b.merge(m)
			first = false
		stack.append_array(n.get_children())

	var x0 := b.position.x - MARGIN
	var z0 := b.position.z - MARGIN
	var nx := int(ceil((b.size.x + 2.0 * MARGIN) / CELL))
	var nz := int(ceil((b.size.z + 2.0 * MARGIN) / CELL))
	var space := _map.get_world_3d().direct_space_state

	# 1. Solid cells: anything WORLD under the cell, dropped from above every building.
	var solid := PackedByteArray()
	solid.resize(nx * nz)
	solid.fill(0)
	for i in nx:
		for j in nz:
			var x := x0 + (i + 0.5) * CELL
			var z := z0 + (j + 0.5) * CELL
			var q := Layers.ray(Vector3(x, b.end.y + 100.0, z), Vector3(x, b.position.y - 60.0, z))
			if not space.intersect_ray(q).is_empty():
				solid[i * nz + j] = 1

	# 2. Exterior: empty cells connected to the grid border.
	var ext := PackedByteArray()
	ext.resize(nx * nz)
	ext.fill(0)
	var queue := PackedInt32Array()
	for i in nx:
		for j in nz:
			var k := i * nz + j
			if (i == 0 or j == 0 or i == nx - 1 or j == nz - 1) and solid[k] == 0:
				ext[k] = 1
				queue.append(k)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var ci := c / nz
		var cj := c % nz
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = ci + d[0]
			var nj: int = cj + d[1]
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
				continue
			var k2 := ni * nz + nj
			if solid[k2] == 0 and ext[k2] == 0:
				ext[k2] = 1
				queue.append(k2)

	# 3. Edges: each playable cell next to an exterior cell, keyed by axis, exterior side and line.
	# Every edge is also kept as a point plus its inward direction, for the coverage check below.
	var runs := {}
	var edges: Array = []
	for i in nx:
		for j in nz:
			if ext[i * nz + j] == 1:
				continue
			if i > 0 and ext[(i - 1) * nz + j] == 1:
				_add(runs, "x", -1, i, j)
				edges.append([Vector2(x0 + i * CELL, z0 + (j + 0.5) * CELL), Vector2(1.0, 0.0)])
			if i < nx - 1 and ext[(i + 1) * nz + j] == 1:
				_add(runs, "x", 1, i + 1, j)
				edges.append([Vector2(x0 + (i + 1) * CELL, z0 + (j + 0.5) * CELL), Vector2(-1.0, 0.0)])
			if j > 0 and ext[i * nz + j - 1] == 1:
				_add(runs, "z", -1, j, i)
				edges.append([Vector2(x0 + (i + 0.5) * CELL, z0 + j * CELL), Vector2(0.0, 1.0)])
			if j < nz - 1 and ext[i * nz + j + 1] == 1:
				_add(runs, "z", 1, j + 1, i)
				edges.append([Vector2(x0 + (i + 0.5) * CELL, z0 + (j + 1) * CELL), Vector2(0.0, -1.0)])

	# 4. Merge contiguous edges into straight wall rects.
	var walls: Array = []
	for key in runs:
		var parts: PackedStringArray = (key as String).split("|")
		var axis := parts[0]
		var side := int(parts[1])
		var line := int(parts[2])
		var along: Array = runs[key]
		along.sort()
		var s := 0
		while s < along.size():
			var e := s
			while e + 1 < along.size() and along[e + 1] == along[e] + 1:
				e += 1
			walls.append(_rect(axis, side, line, along[s], along[e], x0, z0))
			s = e + 1

	var playable := 0
	for k in nx * nz:
		if ext[k] == 0:
			playable += 1

	# 5. Coverage: every edge must be backed by a wall rect. The rect straddles the inset band
	# [INSET - T, INSET] on the playable side of the edge, so probe its centre.
	var miss := 0
	for e in edges:
		var p: Vector2 = e[0] + (e[1] as Vector2) * (INSET - T * 0.5)
		var hit := false
		for w in walls:
			var wl := Vector2(float(w["min"][0]), float(w["min"][1]))
			var wh := Vector2(float(w["max"][0]), float(w["max"][1]))
			if p.x >= wl.x - 0.001 and p.x <= wh.x + 0.001 and p.y >= wl.y - 0.001 and p.y <= wh.y + 0.001:
				hit = true
				break
		if not hit:
			miss += 1
	print("[TRACE] coverage: %d/%d edges backed by a wall (%d uncovered)" % [
		edges.size() - miss, edges.size(), miss])
	var out := {
		"cell": CELL,
		"origin": [x0, z0],
		"grid": [nx, nz],
		"top": b.end.y + TOP_PAD,
		"bottom": BOTTOM,
		"inset": INSET,
		"bounds": [b.position.x, b.position.y, b.position.z, b.end.x, b.end.y, b.end.z],
		"playable_cells": playable,
		"wall_count": walls.size(),
		"walls": walls,
	}
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	# Preview: blue exterior, dark solid, light open ground, red walls. Top of the image is -z.
	var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
	for i in nx:
		for j in nz:
			var k := i * nz + j
			var col := Color(0.2, 0.35, 0.6) if ext[k] == 1 else (Color(0.25, 0.25, 0.25) if solid[k] == 1 else Color(0.85, 0.85, 0.8))
			img.set_pixel(i, j, col)
	for w in walls:
		var lo: Vector2 = WB_v2(w["min"])
		var hi: Vector2 = WB_v2(w["max"])
		var i0 := clampi(int(floor((lo.x - x0) / CELL)), 0, nx - 1)
		var i1 := clampi(int(floor((hi.x - x0) / CELL)), 0, nx - 1)
		var j0 := clampi(int(floor((lo.y - z0) / CELL)), 0, nz - 1)
		var j1 := clampi(int(floor((hi.y - z0) / CELL)), 0, nz - 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				img.set_pixel(i, j, Color(1.0, 0.1, 0.1))
	img.save_png(OUT_PNG)

	print("[TRACE] grid %dx%d cells (%.0f m x %.0f m at %.0f m)  solid %d  playable %d  exterior %d" % [
		nx, nz, nx * CELL, nz * CELL, CELL, _count(solid, 1), playable, nx * nz - playable])
	print("[TRACE] %d wall runs  top %.1f m  %d ms  -> %s" % [
		walls.size(), out["top"], Time.get_ticks_msec() - t0, OUT_JSON])


func _add(runs: Dictionary, axis: String, side: int, line: int, along: int) -> void:
	var key := "%s|%d|%d" % [axis, side, line]
	if not runs.has(key):
		runs[key] = []
	(runs[key] as Array).append(along)


## One wall rect INSET metres inside the edge. `in` points from the wall toward play.
func _rect(axis: String, side: int, line: int, a0: int, a1: int, x0: float, z0: float) -> Dictionary:
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	var inward := Vector2.ZERO
	if axis == "x":
		var lx := x0 + line * CELL
		lo = Vector2(lx - T if side < 0 else lx, z0 + a0 * CELL - T)
		hi = Vector2(lx if side < 0 else lx + T, z0 + (a1 + 1) * CELL + T)
		inward = Vector2(float(-side), 0.0)
	else:
		var lz := z0 + line * CELL
		lo = Vector2(x0 + a0 * CELL - T, lz - T if side < 0 else lz)
		hi = Vector2(x0 + (a1 + 1) * CELL + T, lz if side < 0 else lz + T)
		inward = Vector2(0.0, float(-side))
	# Sit INSET metres inside the edge, and run the ends on by the same amount, so the walls of
	# two perpendicular runs still overlap at every corner instead of leaving a sliver.
	lo += inward * INSET
	hi += inward * INSET
	if axis == "x":
		lo.y -= INSET
		hi.y += INSET
	else:
		lo.x -= INSET
		hi.x += INSET
	return {"min": [lo.x, lo.y], "max": [hi.x, hi.y], "in": [inward.x, inward.y]}


func _count(bytes: PackedByteArray, value: int) -> int:
	var c := 0
	for v in bytes:
		if v == value:
			c += 1
	return c


func WB_v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
