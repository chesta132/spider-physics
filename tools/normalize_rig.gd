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
## Ground clips, built here so `pack()` cannot drop them. Rotations only, no root motion.
## [name, loop s, keys, leg deg, arm deg, lean deg, yaw deg, bob 0..1]
## bob = share of the measured hip offset that plants the stance foot: 1.0 keeps it exactly on the
## street, <1 leaves the run's extension peak airborne. Feet never go below y=0 (see _clip).
const CLIPS := [
	["idle", 2.0, 8, 0.0, 1.5, 0.8, 0.0, 0.0],
	["walk", 1.0, 24, 30.0, 14.0, 2.5, 3.0, 1.0],
	["run", 0.6, 24, 42.0, 34.0, 10.0, 5.0, 0.85],
]
const D2R := PI / 180.0

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
	_sk.name = "Skeleton"  # fixed name: Body's parent path is written from it, so it must be stable
	rig.add_child(_sk)
	_sk.transform = Transform3D.IDENTITY
	_mi.get_parent().remove_child(_mi)
	_sk.add_child(_mi)
	_mi.name = "Body"
	_mi.transform = Transform3D.IDENTITY
	_mi.skeleton = NodePath("..")
	_inst.queue_free()

	# 5. Animation: one library "moves" with idle / walk / run, as a sibling of the Skeleton.
	#    In the tree first: the foot calibration below reads posed bone transforms, which a
	#    Skeleton3D only computes while it is inside the tree.
	get_root().add_child(rig)
	_build_anim(rig)

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
	for i in _sk.get_bone_count():
		var p := _sk.get_bone_parent(i)
		var b := _sk.get_bone_global_rest(i)
		print("BONE %d %-11s parent %-11s pos (%.3f, %.3f, %.3f)" % [i, _sk.get_bone_name(i),
			_sk.get_bone_name(p) if p >= 0 else "-", b.origin.x, b.origin.y, b.origin.z])
	var box := _bounds()
	print("RESULT bounds size ", box.size, " lo ", box.position)
	var ap: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
	if ap:
		for ln in ap.get_animation_library_list():
			var lib := ap.get_animation_library(ln)
			for cn in lib.get_animation_list():
				var an := lib.get_animation(cn)
				print("CLIP %s/%s len %.2f s tracks %d loop %d" % [ln, cn, an.length, an.get_track_count(), an.loop_mode])


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


## AnimationPlayer + library "moves" (idle / walk / run) under PlayerRig, sibling of the Skeleton.
## Every clip animates the same 8 tracks, so a crossfade between any two of them cannot leave a
## bone stranded at a value the incoming clip never keys.
func _build_anim(rig: Node3D) -> void:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		lib.add_animation(c[0], _clip(c))
	ap.add_animation_library("moves", lib)


func _clip(c: Array) -> Animation:
	var a := Animation.new()
	a.length = c[1]
	a.loop_mode = Animation.LOOP_LINEAR
	var rot := {}
	for b in ["Torso", "Head", "Arm.L", "Arm.R", "Leg.L", "Leg.R"]:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, "Skeleton:" + b)
		rot[b] = t
	# Position tracks carry the bone's ABSOLUTE local position in Godot 4 (a bare offset would
	# drop the rest offset and lift the whole rig), so start from rest and add the bob.
	var rest_hips := _sk.get_bone_rest(_sk.find_bone("Hips")).origin
	var rest_head := _sk.get_bone_rest(_sk.find_bone("Head")).origin
	var hips := a.add_track(Animation.TYPE_POSITION_3D)  # bob only: X/Z stay at rest, physics owns those
	a.track_set_path(hips, "Skeleton:Hips")
	var head := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(head, "Skeleton:Head")
	var keys: int = c[2]
	for i in keys + 1:  # last key repeats phase 0, so the loop closes exactly
		var p := float(i) / float(keys)
		var t := p * float(c[1])
		# Hip bob is calibrated, not guessed: the foot is one rigid box with the leg, so its toe
		# dips below y=0 in mid-swing and lifts at full stride. Offset the hips by the measured
		# lowest vertex so the stance foot sits on the street; c[7] < 1 leaves the run peak airborne.
		var dy := -float(c[7]) * _lowest_y(float(c[3]) * sin(TAU * p))
		var pose := _pose(c, fmod(p, 1.0), dy)
		for b in rot:
			a.rotation_track_insert_key(rot[b], t, Quaternion.from_euler(pose[b]))
		a.position_track_insert_key(hips, t, rest_hips + Vector3(0.0, pose["hips_dy"], 0.0))
		a.position_track_insert_key(head, t, rest_head + Vector3(0.0, pose["head_dy"], 0.0))
	return a


## Lowest world y of the drawn mesh with both legs swung to ±deg — the pose the clips use.
func _lowest_y(deg: float) -> float:
	var a := deg * D2R
	_sk.reset_bone_poses()
	_sk.set_bone_pose_rotation(_sk.find_bone("Leg.L"), Quaternion(Vector3.RIGHT, a))
	_sk.set_bone_pose_rotation(_sk.find_bone("Leg.R"), Quaternion(Vector3.RIGHT, -a))
	_sk.force_update_all_bone_transforms()
	var skin := _mi.skin
	var arr := (_mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / verts.size()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		mats.append(_sk.get_bone_global_pose(_sk.find_bone(skin.get_bind_name(i))) * skin.get_bind_pose(i))
	var lo := 1e9
	for v in verts.size():
		var p := Vector3.ZERO
		var wsum := 0.0
		for k in stride:
			var w: float = weights[v * stride + k]
			if w == 0.0:
				continue
			p += (mats[bones[v * stride + k]] * verts[v]) * w
			wsum += w
		if wsum >= 0.001:
			lo = minf(lo, (p / wsum).y)
	_sk.reset_bone_poses()
	return lo


## Pose at phase p in [0,1). Rotations in radians about the world-aligned bone axes, model faces +Z.
## A positive X rotation swings a downward-pointing limb backwards (foot toward -Z).
func _pose(c: Array, p: float, hips_dy: float) -> Dictionary:
	var ph := TAU * p
	var s := sin(ph)
	var leg: float = c[3]
	var arm: float = c[4]
	var lean: float = c[5]
	var yaw: float = c[6]
	var la := leg * s * D2R
	if leg == 0.0:  # idle: breathe, sway, head bob, arms a degree or two off rest
		return {
			"Torso": Vector3(lean * s * D2R, 0.0, 1.4 * s * D2R),
			"Head": Vector3(-lean * s * D2R, 0.0, 0.0),
			"Arm.L": Vector3(arm * s * D2R, 0.0, 2.0 * D2R),
			"Arm.R": Vector3(-arm * s * D2R, 0.0, -2.0 * D2R),
			"Leg.L": Vector3.ZERO, "Leg.R": Vector3.ZERO,
			"hips_dy": 0.0, "head_dy": 0.005 * sin(2.0 * ph),
		}
	return {
		"Torso": Vector3((lean + lean * 0.15 * sin(2.0 * ph)) * D2R, yaw * s * D2R, 0.8 * s * D2R),
		"Head": Vector3(-lean * 0.7 * D2R, -yaw * 0.5 * s * D2R, 0.0),
		"Arm.L": Vector3(-arm * s * D2R, 0.0, 2.0 * D2R),
		"Arm.R": Vector3(arm * s * D2R, 0.0, -2.0 * D2R),
		"Leg.L": Vector3(la, 0.0, 0.0),
		"Leg.R": Vector3(-la, 0.0, 0.0),
		"hips_dy": hips_dy,
		"head_dy": 0.0,
	}


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
