extends SceneTree
## Bake the lego glTF into an animation-ready rig scene: metres, feet on y=0, body on the origin,
## unit scale, and bones sitting at their joints with world-aligned axes (so "rotate Arm.L about X"
## swings it forward instead of in some inherited 127-degree frame).
## Re-run after touching the source glTF:  godot --headless -s tools/normalize_rig.gd
const SRC := "res://assets/player_lego/scene.gltf"
const OUT := "res://assets/player_lego/player_rig.tscn"
const HEIGHT := 1.8  # matches the player capsule
## Joint order in the source skin; the glTF names carry Sketchfab's node-id suffixes (Root_8, ...).
const NAMES := ["Root", "Hips", "Torso", "Head", "Shoulder.L", "Arm.L", "Shoulder.R", "Arm.R",
	"Leg.L", "Leg.R"]

var _f := 0
var _inst: Node3D
var _sk: Skeleton3D
var _mi: MeshInstance3D


func _initialize() -> void:
	_inst = (load(SRC) as PackedScene).instantiate()
	get_root().add_child(_inst)


func _process(_d: float) -> bool:
	if _f < 3:  # a frame of tree so the import chain's transforms are live
		_f += 1
		return false
	_sk = _find(_inst) as Skeleton3D
	_mi = _mesh(_inst)
	if _sk == null or _mi == null:
		print("FAIL no skeleton/mesh in ", SRC)
		quit(1)
		return true

	# 1. Fit: metres, feet on y=0, horizontal centre on the origin. t is that vertex transform.
	var box := _bounds()
	var c := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
	var t := Transform3D(Basis().scaled(Vector3.ONE * (HEIGHT / box.size.y)), -c * (HEIGHT / box.size.y))
	var ti := t.affine_inverse()

	# 2. Vertices into metres. Uniform scale, so normals and tangents survive untouched.
	#    CUSTOM0 (the glTF's third UV set) is dropped: it comes back as a PackedFloat32Array and
	#    add_surface_from_arrays only accepts a PackedByteArray there. Nothing samples it.
	var src_mesh := _mi.mesh as ArrayMesh
	var mesh := ArrayMesh.new()
	for s in src_mesh.get_surface_count():
		var arr := src_mesh.surface_get_arrays(s)
		arr[Mesh.ARRAY_CUSTOM0] = null
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] = t * vs[i]
		arr[Mesh.ARRAY_VERTEX] = vs
		mesh.add_surface_from_arrays(src_mesh.surface_get_primitive_type(s), arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, src_mesh.surface_get_material(s))
	_mi.mesh = mesh

	# 3. Bones: same world position, identity orientation. Snapshot first — setting a rest rewrites it.
	var skin := _mi.skin.duplicate() as Skin
	var bind_names := PackedStringArray()
	var old_world: Array[Transform3D] = []
	for i in _sk.get_bone_count():
		old_world.append(_sk.global_transform * _sk.get_bone_global_rest(i))
	var bind_bone := PackedInt32Array()
	for i in skin.get_bind_count():
		bind_names.append(skin.get_bind_name(i))
		bind_bone.append(_sk.find_bone(bind_names[i]))
	# No set_bone_global_rest in Godot 4: build the new globals, then write locals parent-first.
	var new_global: Array[Transform3D] = []
	for i in _sk.get_bone_count():
		new_global.append(Transform3D(Basis(), t * old_world[i].origin))
	for i in _sk.get_bone_count():
		var p := _sk.get_bone_parent(i)
		_sk.set_bone_rest(i, new_global[i] if p < 0 else new_global[p].affine_inverse() * new_global[i])
		_sk.set_bone_name(i, NAMES[i] if i < NAMES.size() else "Bone%d" % i)
	# Bind pose is the inverse bind matrix. Sandwich the old bone world transform through t so the
	# mesh draws at its new metre positions and keeps its shape.
	for i in skin.get_bind_count():
		var b := bind_bone[i]
		var new_g := new_global[b]
		skin.set_bind_pose(i, new_g.affine_inverse() * t * old_world[b] * skin.get_bind_pose(i) * ti)
		skin.set_bind_name(i, _sk.get_bone_name(b))
	_mi.skin = skin
	_sk.reset_bone_poses()

	# 4. Rebuild a clean tree: PlayerRig > Skeleton > Body, no Sketchfab wrappers, no scale nodes.
	var rig := Node3D.new()
	rig.name = "PlayerRig"
	_sk.get_parent().remove_child(_sk)
	rig.add_child(_sk)
	_sk.transform = Transform3D.IDENTITY
	_mi.get_parent().remove_child(_mi)
	_sk.add_child(_mi)
	_mi.name = "Body"
	_mi.transform = Transform3D.IDENTITY
	_mi.skeleton = NodePath("..")
	_inst.queue_free()

	# Runtime-built children carry no owner, and pack() only serializes owned nodes.
	_set_owner(rig, rig)
	var ps := PackedScene.new()
	var err := ps.pack(rig)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("RESULT saved ", OUT, " err=", err)
	_report(rig)
	quit(0 if err == OK else 1)
	return true


func _report(rig: Node3D) -> void:
	get_root().add_child(rig)
	for i in _sk.get_bone_count():
		var p := _sk.get_bone_parent(i)
		var b := _sk.get_bone_global_rest(i)
		print("BONE %d %-11s parent %-11s pos (%.3f, %.3f, %.3f)" % [i, _sk.get_bone_name(i),
			_sk.get_bone_name(p) if p >= 0 else "-", b.origin.x, b.origin.y, b.origin.z])
	var box := _bounds()
	print("RESULT bounds size ", box.size, " lo ", box.position)


## World-space AABB of the drawn (skinned, rest-pose) mesh — the mesh's own AABB is bind-space.
func _bounds() -> AABB:
	var skin := _mi.skin
	var arr := (_mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / verts.size()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		mats.append(_sk.get_bone_global_rest(_sk.find_bone(skin.get_bind_name(i))) * skin.get_bind_pose(i))
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for v in verts.size():
		var p := Vector3.ZERO
		var wsum := 0.0
		for k in stride:
			var w: float = weights[v * stride + k]
			if w == 0.0:
				continue
			p += (mats[bones[v * stride + k]] * verts[v]) * w
			wsum += w
		if wsum < 0.001:
			continue
		p = _sk.global_transform * (p / wsum)
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


func _set_owner(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_set_owner(c, owner)


func _find(n: Node) -> Node:
	if n is Skeleton3D:
		return n
	for ch in n.get_children():
		var r := _find(ch)
		if r:
			return r
	return null


func _mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for ch in n.get_children():
		var r := _mesh(ch)
		if r:
			return r
	return null
