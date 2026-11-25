extends Node3D
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
## Bakes collision for a visual-only map (Sketchfab rips ship no physics).
## One StaticBody3D + ConcavePolygonShape3D per MeshInstance3D, in mesh-local space, so the shape
## inherits whatever scale/rotation the import chain applies — no vertex-space maths.
## Winding is corrected against each triangle's own vertex normals: rips wind faces
## inconsistently, and a face whose normal points inward makes wall.gd grab the wrong way and
## drag the body into the building. Correcting here fixes every raycast user at once
## (wall attach, corner wrap, zip perch, web anchor).
## ponytail: baked at load. Pre-bake to a .res if load time or draw setup ever hurts.

var _flipped := 0
var _no_normals := 0


func _ready() -> void:
	var t := Time.get_ticks_msec()
	var bodies := 0
	var tris := 0
	for mi in _meshes(self):
		if _already_has_collision(mi):
			continue
		var faces := _faces(mi)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true  # roads and walls are single-sided sheets
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.add_child(cs)
		mi.add_child(body)
		bodies += 1
		tris += faces.size() / 3
	print("[MAP] baked %d bodies / %d tris in %d ms (%d triangles flipped, %d meshes without normals)" % [
		bodies, tris, Time.get_ticks_msec() - t, _flipped, _no_normals])


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			out.append(c)
		out.append_array(_meshes(c))
	return out


func _already_has_collision(mi: Node) -> bool:
	for c in mi.get_children():
		if c is StaticBody3D or c is CollisionShape3D or c is CollisionObject3D:
			return true
	return false


## Triangle soup in mesh-local space, with each triangle wound so its face normal agrees with the
## vertex normals the artist stored.
func _faces(mi: MeshInstance3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
		var use_idx := idx.size() > 0
		var count := idx.size() if use_idx else v.size()
		var have_normals := nr.size() == v.size()
		if not have_normals:
			_no_normals += 1
		var i := 0
		while i + 2 < count:
			var ia := idx[i] if use_idx else i
			var ib := idx[i + 1] if use_idx else i + 1
			var ic := idx[i + 2] if use_idx else i + 2
			i += 3
			if ia < 0 or ib < 0 or ic < 0 or ia >= v.size() or ib >= v.size() or ic >= v.size():
				continue
			var a := v[ia]
			var b := v[ib]
			var c := v[ic]
			var fn := (b - a).cross(c - a)
			if fn.length_squared() < 1e-14:
				continue  # degenerate
			if have_normals and fn.dot(nr[ia] + nr[ib] + nr[ic]) < 0.0:
				var t := b
				b = c
				c = t
				_flipped += 1
			faces.append(a)
			faces.append(b)
			faces.append(c)
	return faces