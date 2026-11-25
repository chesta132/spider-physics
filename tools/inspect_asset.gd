extends SceneTree
## Measure a map or character asset before wiring it in.
## Reports: mesh/collision counts, world AABB (size + origin height), the orientation mix of
## surface normals, and — for rigged models — the AABB as the renderer actually draws it, computed
## by pushing every vertex through its bone matrices (the raw mesh AABB is bind-space and lies).
## Usage: godot --headless -s tools/inspect_asset.gd -- res://assets/maps/scene.gltf
## Import first if the asset is new: godot --headless --import

const NORMAL_SAMPLE := 4  # inspect every Nth vertex for the orientation mix; big maps are slow

var _path := ""
var _root: Node
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless -s tools/inspect_asset.gd -- <path>")
		quit(1)
		return
	_path = args[0]
	var ps := load(_path) as PackedScene
	if ps == null:
		print("NOT a PackedScene (imported yet?): ", _path)
		quit(1)
		return
	_root = ps.instantiate()
	get_root().add_child(_root)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false  # global transforms only resolve once inside the tree
	_report(_root, _path)
	return true


func _report(root: Node, path: String) -> void:
	print("=== ", path)
	var aabb := AABB()
	var has_box := false
	var meshes := 0
	var tris := 0
	var shapes := 0
	var bodies := 0
	var skins := 0
	var n_up := 0
	var n_down := 0
	var n_vert := 0
	var n_slope := 0
	var groups := {}

	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D:
			bodies += 1
		if n is CollisionShape3D:
			shapes += 1
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			var bones := AABB()
			var first := true
			for i in sk.get_bone_count():
				var p := sk.global_transform * sk.get_bone_global_rest(i).origin
				bones = AABB(p, Vector3.ZERO) if first else bones.expand(p)
				first = false
			print("skeleton: %d bones  rest bone AABB min %s max %s size %s" % [
				sk.get_bone_count(), bones.position, bones.end, bones.size])
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			meshes += 1
			var mi := n as MeshInstance3D
			var box := _world_aabb(mi)
			aabb = box if not has_box else aabb.merge(box)
			has_box = true
			var key: String = _group_of(_branch_root(root), mi)
			var g: Array = groups.get(key, [AABB(), true, 0])
			g[0] = box if g[1] else (g[0] as AABB).merge(box)
			g[1] = false
			g[2] = int(g[2]) + 1
			groups[key] = g
			if mi.skin:
				skins += 1
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null and idx.size() > 0 else v.size()) / 3
				var i := 0
				while i < nr.size():
					var ny := absf(nr[i].y)
					if ny > 0.94:
						if nr[i].y > 0.0:
							n_up += 1
						else:
							n_down += 1
					elif ny < 0.35:
						n_vert += 1
					else:
						n_slope += 1
					i += NORMAL_SAMPLE
		for c in n.get_children():
			stack.append(c)

	print("meshes: %d  tris: %d  skinned: %d  collision bodies: %d  shapes: %d" % [meshes, tris, skins, bodies, shapes])
	if has_box:
		print("AABB min: %s  max: %s" % [aabb.position, aabb.end])
		print("size (x,y,z metres): %s" % [aabb.size])
		print("lowest y = %.3f  ->  %s" % [aabb.position.y, _origin_hint(aabb)])
	else:
		print("AABB: no meshes found")
	var total := n_up + n_down + n_vert + n_slope
	if total > 0:
		print("normals: up %.1f%%  down %.1f%%  vertical %.1f%%  sloped %.1f%%  (sampled)" % [
			100.0 * n_up / total, 100.0 * n_down / total, 100.0 * n_vert / total, 100.0 * n_slope / total])
		print("verdict: ", _verdict(bodies, shapes, n_vert, n_slope, total))
	if groups.size() > 1:
		print("--- top-level groups (%d) ---" % groups.size())
		var keys := groups.keys()
		keys.sort()
		for k in keys:
			var g: Array = groups[k]
			var b: AABB = g[0]
			print("  %-26s %4d meshes  min %s  size %s" % [k, g[2], _v(b.position), _v(b.size)])


## AABB as drawn: for a skinned mesh the raw mesh bounds are bind-space and wrong, so transform
## every vertex by its bone matrices (global rest * inverse bind) first.
func _world_aabb(mi: MeshInstance3D) -> AABB:
	var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	if sk == null or skin == null:
		return mi.global_transform * mi.mesh.get_aabb()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bi := skin.get_bind_bone(i)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(i))  # importer uses named binds
		# one entry per bind index: ARRAY_BONES indexes this list, not the bone ids
		mats.append(sk.get_bone_global_rest(bi) * skin.get_bind_pose(i) if bi >= 0 else Transform3D.IDENTITY)
	var base := sk.global_transform
	var out := AABB()
	var first := true
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null:
			continue
		for vi in verts.size():
			var p := Vector3.ZERO
			for k in 4:
				var bi: int = bones[vi * 4 + k]
				var w: float = weights[vi * 4 + k]
				if w > 0.0 and bi >= 0 and bi < mats.size():
					p += (mats[bi] * verts[vi]) * w
			p = base * p
			out = AABB(p, Vector3.ZERO) if first else out.expand(p)
			first = false
	return out


## Sketchfab wraps everything in a single-child chain (Sketchfab_model → map1.fbx → RootNode →
## map1). Walk past it so the groups are the real content buckets.
func _branch_root(n: Node) -> Node:
	while n.get_child_count() == 1:
		n = n.get_child(0)
	return n


func _group_of(branch: Node, n: Node) -> String:
	var cur := n
	while cur and cur.get_parent() != branch:
		cur = cur.get_parent()
	return str(cur.name) if cur else str(n.name)


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _origin_hint(aabb: AABB) -> String:
	if absf(aabb.position.y) < 0.05:
		return "origin at ground level (feet-at-0 convention)"
	if aabb.position.y < 0.0:
		return "sinks %.2f m below y=0 — origin is not at the feet" % -aabb.position.y
	return "floats %.2f m above y=0 — needs a -%.2f m offset" % [aabb.position.y, aabb.position.y]


func _verdict(bodies: int, shapes: int, vert: int, slope: int, total: int) -> String:
	var out := ""
	if bodies == 0 or shapes == 0:
		out += "NO COLLISION -> generate it. "
	if total > 0 and float(vert) / total < 0.15:
		out += "few vertical faces -> little to crawl/zip on. "
	if total > 0 and float(slope) / total > 0.25:
		out += "many sloped faces -> wall attach (|n.y|<=0.35) will refuse them. "
	return out if out != "" else "geometry looks usable for zip/wall."