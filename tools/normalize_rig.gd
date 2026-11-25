extends SceneTree
## Bake the LEGO glTF into a fitted, animation-ready rig. The skeleton is rebuilt with joints at
## measured shoulder/elbow/wrist/hip/knee pivots and the mesh is re-weighted to the new hierarchy.
## Re-run: godot --headless -s tools/normalize_rig.gd
const SRC := "res://assets/player_lego/scene.gltf"
const OUT := "res://assets/player_lego/player_rig.tscn"
const HEIGHT := 1.8
const D2R := PI / 180.0
## Superhero landing, matched to the reference figure: hips dropped to knee height, torso pitched
## forward, head lifted, right leg thrown wide with a soft knee, left leg folded deep as the support
## leg, right hand planted on the street, left arm thrown out horizontally. Left side of the model is
## +X (it faces +Z), so the reference's "figure's right" is the .R chain here.
const LAND_LEAN := 76.0      # deg, torso pitch forward: reference reads ~55-60 on a long-armed
                             # figure; the short LEGO arm needs a steeper chest to reach the street
const LAND_HEAD := -66.0     # deg, head counter-rotated to keep the mask looking forward
const LAND_SUPPORT_THIGH := -70.0   # .L, thigh swung forward
const LAND_SUPPORT_SPLAY := 26.0    # .L, knee pushed out to the side
const LAND_SUPPORT_KNEE := 118.0    # .L, deep fold: this leg carries the crouch
const LAND_WIDE_THIGH := 0.0        # .R, no fore/aft: the wide leg is a pure side diagonal
const LAND_WIDE_SPLAY := -50.0      # .R, thigh thrown out wide: one straight diagonal to the foot
const LAND_WIDE_KNEE := 0.0         # .R, locked straight (any knee flex here reads as a frog squat)
const LAND_PLANT_ARM := -54.0       # .R upper arm, reaching down/forward to the street
const LAND_PLANT_ELBOW := -16.0     # .R forearm, almost straight
const LAND_OPEN_ARM := 78.0         # .L upper arm, thrown out to the side (Z abduction)
const LAND_OPEN_ELBOW := -14.0      # .L forearm, slight bend
const BLEND := 0.05
const NAMES := ["Root", "Hips", "Torso", "Head", "Shoulder.L", "Arm.L", "Shoulder.R", "Arm.R", "Leg.L", "Leg.R"]
## Measured from the normalized mesh. Left side; right side mirrors X.
## shoulder, elbow, wrist, hip, knee. LowerLeg includes the LEGO foot as one control.
const JOINTS := {
	"Shoulder": Vector3(0.268, 1.14, -0.008),
	"Elbow": Vector3(0.358, 0.95, -0.05),
	"Wrist": Vector3(0.40, 0.72, -0.07),
	"Hip": Vector3(0.176, 0.66, 0.0),
	"Knee": Vector3(0.176, 0.40, 0.0),
}
## Gait parameters per clip. Angles in degrees; "swing" is the amplitude about the joint's X axis.
## knee/knee_base: flex peaks as the leg passes under the body swinging forward, never in stance.
## elbow/elbow_swing: runners hold the elbow bent throughout; walkers nearly straighten it.
const CLIPS := [
	{"name": "idle", "kind": "gait", "len": 2.0, "keys": 12, "thigh": 0.0, "knee": 0.0, "knee_base": 0.0,
		"arm": 1.5, "elbow": 3.0, "elbow_swing": 0.0, "lean": 0.8, "yaw": 0.0, "bob": 0.0,
		"shoulder": 0.0, "splay": 2.0},
	{"name": "walk", "kind": "gait", "len": 1.0, "keys": 32, "thigh": 32.0, "knee": 34.0, "knee_base": 3.0,
		"arm": 20.0, "elbow": 8.0, "elbow_swing": 16.0, "lean": 2.5, "yaw": 3.0, "bob": 1.0,
		"shoulder": 0.04, "splay": 9.0},
	{"name": "run", "kind": "gait", "len": 0.6, "keys": 48, "thigh": 46.0, "knee": 62.0, "knee_base": 6.0,
		"arm": 40.0, "elbow": 68.0, "elbow_swing": 22.0, "lean": 10.0, "yaw": 5.0, "bob": 0.92,
		"shoulder": 0.05, "splay": 16.0},
	## Air clips LOOP on purpose: a non-looping clip is reset to the rest pose by the mixer the
	## moment it ends, so a held jump/landing pose has to loop. The snap into each pose comes from
	## the controller's short crossfade, not from a ramp inside the clip.
	{"name": "jump", "kind": "jump", "len": 0.40, "keys": 8, "loop": true},
	{"name": "fall", "kind": "fall", "len": 0.60, "keys": 12, "loop": true},
	{"name": "land", "kind": "land", "len": 0.80, "keys": 16, "loop": true},
]
const ROT_BONES := ["Torso", "Head", "Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "Forearm.L", "Forearm.R",
	"Hand.L", "Hand.R", "Thigh.L", "Thigh.R", "LowerLeg.L", "LowerLeg.R"]

var _f := 0
var _inst: Node3D
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _joint_shift := Vector3.ZERO

func _initialize() -> void:
	_inst = (load(SRC) as PackedScene).instantiate()
	get_root().add_child(_inst)

func _process(_d: float) -> bool:
	if _f < 3:
		_f += 1
		return false
	_sk = _find(_inst) as Skeleton3D
	_mi = _mesh(_inst)
	if _sk == null or _mi == null:
		print("FAIL no skeleton/mesh in ", SRC)
		quit(1)
		return true

	# Fit source geometry to 1.8 m, feet at y=0, centered horizontally.
	var box := _bounds()
	var c := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
	var t := Transform3D(Basis().scaled(Vector3.ONE * (HEIGHT / box.size.y)), -c * (HEIGHT / box.size.y))
	var ti := t.affine_inverse()
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

	# Normalize source bones, then capture the rendered rest mesh in skeleton space.
	var old_skin := _mi.skin.duplicate() as Skin
	_sk.reset_bone_poses()
	var old_world: Array[Transform3D] = []
	for i in _sk.get_bone_count():
		old_world.append(_sk.global_transform * _sk.get_bone_global_rest(i))
	var old_bind_bone := PackedInt32Array()
	for i in old_skin.get_bind_count():
		old_bind_bone.append(_sk.find_bone(old_skin.get_bind_name(i)))
	var old_global: Array[Transform3D] = []
	for i in _sk.get_bone_count():
		old_global.append(Transform3D(Basis(), t * old_world[i].origin))
	for i in _sk.get_bone_count():
		var parent := _sk.get_bone_parent(i)
		_sk.set_bone_rest(i, old_global[i] if parent < 0 else old_global[parent].affine_inverse() * old_global[i])
		_sk.set_bone_name(i, NAMES[i] if i < NAMES.size() else "Bone%d" % i)
	for i in old_skin.get_bind_count():
		var b := old_bind_bone[i]
		old_skin.set_bind_pose(i, old_global[b].affine_inverse() * t * old_world[b] * old_skin.get_bind_pose(i) * ti)
		old_skin.set_bind_name(i, _sk.get_bone_name(b))
	_mi.skin = old_skin
	_sk.reset_bone_poses()
	var rest := _skinned(_sk, _mi)
	var rest_lo := 1e9
	for q in rest:
		rest_lo = minf(rest_lo, q.y)
	# The imported skeleton carries a small fitted-space floor offset. Remove only its measured floor
	# height; this keeps the new joints in the same coordinate frame as the fitted mesh.
	_joint_shift = Vector3(0.0, rest_lo, 0.0)
	for i in rest.size():
		rest[i] -= _joint_shift
	var src := (_mi.mesh as ArrayMesh).surface_get_arrays(0)
	var prim := (_mi.mesh as ArrayMesh).surface_get_primitive_type(0)
	var material := (_mi.mesh as ArrayMesh).surface_get_material(0)

	# Build the expanded hierarchy and rebind every vertex to new controls.
	var table := _bone_table(_sk)
	var new_sk := _build_skeleton(table)
	var index := {}
	for i in new_sk.get_bone_count():
		index[new_sk.get_bone_name(i)] = i
	var new_mesh := _rebind_mesh(src, rest, old_skin, index, prim, material)
	var new_skin := Skin.new()
	for row in table:
		new_skin.add_bind(index[row[0]], new_sk.get_bone_global_rest(index[row[0]]).affine_inverse())
		new_skin.set_bind_name(new_skin.get_bind_count() - 1, row[0])

	var rig := Node3D.new()
	rig.name = "PlayerRig"
	rig.add_child(new_sk)
	_mi.get_parent().remove_child(_mi)
	new_sk.add_child(_mi)
	_mi.name = "Body"
	_mi.transform = Transform3D.IDENTITY
	_mi.skeleton = NodePath("..")
	_mi.mesh = new_mesh
	_mi.skin = new_skin
	_inst.queue_free()
	_sk = new_sk
	get_root().add_child(rig)

	var after := _skinned(_sk, _mi)
	var worst := 0.0
	for i in rest.size():
		worst = maxf(worst, rest[i].distance_to(after[i]))
	print("REST max vertex drift after rebind %.6f m" % worst)
	if worst > 0.001:
		print("FAIL rest pose changed by the rebind")
		quit(1)
		return true
	_build_anim(rig)
	_set_owner(rig, rig)
	var packed := PackedScene.new()
	var err := packed.pack(rig)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("RESULT saved ", OUT, " err=", err)
	_report(rig)
	quit(0 if err == OK else 1)
	return true

func _bone_table(old: Skeleton3D) -> Array:
	var rows := []
	for b in ["Root", "Hips", "Torso", "Head"]:
		var p := "" if b == "Root" else ("Root" if b == "Hips" else ("Hips" if b == "Torso" else "Torso"))
		rows.append([b, p, old.get_bone_global_rest(old.find_bone(b)).origin - _joint_shift])
	for side in ["L", "R"]:
		var m := 1.0 if side == "L" else -1.0
		var shoulder := Vector3(JOINTS["Shoulder"].x * m, JOINTS["Shoulder"].y, JOINTS["Shoulder"].z)
		var elbow := Vector3(JOINTS["Elbow"].x * m, JOINTS["Elbow"].y, JOINTS["Elbow"].z)
		var wrist := Vector3(JOINTS["Wrist"].x * m, JOINTS["Wrist"].y, JOINTS["Wrist"].z)
		var hip := Vector3(JOINTS["Hip"].x * m, JOINTS["Hip"].y, JOINTS["Hip"].z)
		var knee := Vector3(JOINTS["Knee"].x * m, JOINTS["Knee"].y, JOINTS["Knee"].z)
		rows.append(["Shoulder." + side, "Torso", shoulder])
		rows.append(["UpperArm." + side, "Shoulder." + side, shoulder])
		rows.append(["Forearm." + side, "UpperArm." + side, elbow])
		rows.append(["Hand." + side, "Forearm." + side, wrist])
		rows.append(["Thigh." + side, "Hips", hip])
		rows.append(["LowerLeg." + side, "Thigh." + side, knee])
	return rows

func _build_skeleton(rows: Array) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var joints := {}
	for row in rows:
		joints[row[0]] = row[2]
		sk.add_bone(row[0])
	for row in rows:
		var i := sk.find_bone(row[0])
		var p: String = row[1]
		if p == "":
			sk.set_bone_rest(i, Transform3D(Basis(), row[2]))
		else:
			sk.set_bone_parent(i, sk.find_bone(p))
			sk.set_bone_rest(i, Transform3D(Basis(), row[2] - joints[p]))
	return sk

func _rebind_mesh(src: Array, rest: PackedVector3Array, old_skin: Skin, index: Dictionary, prim: int, material: Material) -> ArrayMesh:
	var old_bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var old_weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var n := rest.size()
	var stride := old_bones.size() / n
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	out_b.resize(4 * n)
	out_w.resize(4 * n)
	for v in n:
		var arm_l := 0.0
		var arm_r := 0.0
		var leg_l := 0.0
		var leg_r := 0.0
		var acc := {}
		for k in stride:
			var w: float = old_weights[v * stride + k]
			if w <= 0.0:
				continue
			var name := old_skin.get_bind_name(old_bones[v * stride + k])
			if name.ends_with(".L") and (name.begins_with("Arm") or name.begins_with("Shoulder")):
				arm_l += w
			elif name.ends_with(".R") and (name.begins_with("Arm") or name.begins_with("Shoulder")):
				arm_r += w
			elif name == "Leg.L":
				leg_l += w
			elif name == "Leg.R":
				leg_r += w
			else:
				_add(acc, index.get(name, index["Torso"]), w)
		_assign_limb(acc, index, "L", rest[v].y, arm_l, leg_l)
		_assign_limb(acc, index, "R", rest[v].y, arm_r, leg_r)
		var pairs := []
		for key in acc:
			pairs.append([acc[key], key])
		pairs.sort_custom(func(a, b): return a[0] > b[0])
		var total := 0.0
		for j in mini(4, pairs.size()):
			total += pairs[j][0]
		for j in mini(4, pairs.size()):
			if total > 0.0:
				out_b[4 * v + j] = pairs[j][1]
				out_w[4 * v + j] = pairs[j][0] / total
	var arr := src.duplicate()
	arr[Mesh.ARRAY_VERTEX] = rest
	arr[Mesh.ARRAY_BONES] = out_b
	arr[Mesh.ARRAY_WEIGHTS] = out_w
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(prim, arr)
	mesh.surface_set_material(0, material)
	return mesh

func _assign_limb(acc: Dictionary, index: Dictionary, side: String, y: float, arm: float, leg: float) -> void:
	if arm > 0.0:
		var upper := smoothstep(0.95 - BLEND, 0.95 + BLEND, y)
		var hand := 1.0 - smoothstep(0.72 - BLEND, 0.72 + BLEND, y)
		_add(acc, index["UpperArm." + side], arm * upper)
		_add(acc, index["Forearm." + side], arm * maxf(0.0, 1.0 - upper - hand))
		_add(acc, index["Hand." + side], arm * hand)
	if leg > 0.0:
		var thigh := smoothstep(0.40 - BLEND, 0.40 + BLEND, y)
		_add(acc, index["Thigh." + side], leg * thigh)
		_add(acc, index["LowerLeg." + side], leg * (1.0 - thigh))

func _add(acc: Dictionary, key: int, weight: float) -> void:
	acc[key] = acc.get(key, 0.0) + weight

func _skinned(sk: Skeleton3D, mi: MeshInstance3D, posed: bool = false) -> PackedVector3Array:
	sk.force_update_all_bone_transforms()
	var skin := mi.skin
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride := bones.size() / verts.size()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bi := sk.find_bone(skin.get_bind_name(i))
		mats.append((sk.get_bone_global_pose(bi) if posed else sk.get_bone_global_rest(bi)) * skin.get_bind_pose(i))
	var out := PackedVector3Array()
	out.resize(verts.size())
	for v in verts.size():
		var p := Vector3.ZERO
		var ws := 0.0
		for k in stride:
			var w: float = weights[v * stride + k]
			if w > 0.0:
				p += (mats[bones[v * stride + k]] * verts[v]) * w
				ws += w
		out[v] = p / ws if ws > 0.0 else verts[v]
	return out

func _build_anim(rig: Node3D) -> void:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		lib.add_animation(c["name"], _clip(c))
	ap.add_animation_library("moves", lib)


func _clip(c: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = c["len"]
	a.loop_mode = Animation.LOOP_LINEAR if c.get("loop", true) else Animation.LOOP_NONE
	var tracks := {}
	for b in ROT_BONES:
		tracks[b] = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tracks[b], "Skeleton:" + b)
	var hips := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hips, "Skeleton:Hips")
	var head := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(head, "Skeleton:Head")
	var rest_hips := _sk.get_bone_rest(_sk.find_bone("Hips")).origin
	var rest_head := _sk.get_bone_rest(_sk.find_bone("Head")).origin
	var keys: int = c["keys"]
	for i in keys + 1:  # last key repeats phase 0, so the loop closes exactly
		var p := float(i) / float(keys)
		var time := p * float(c["len"])
		# Hip bob is calibrated, not guessed: the foot is one rigid box with the leg, so its toe
		# dips in mid-swing. Lift the hips by the measured lowest vertex so the stance foot sits
		# on the street; bob < 1 leaves the run's extension peak airborne.
		var dy := 0.0
		if c["kind"] == "gait" and float(c["bob"]) > 0.0:
			dy = -float(c["bob"]) * _lowest_y(_leg_pose(c, p))
		elif c["kind"] == "land":
			# Calibrate against the WHOLE pose, not just the legs: the planted hand reaches as low as
			# the feet, and whichever is lower must sit on the street or the figure floats.
			dy = -_lowest_y_pose(_air_pose("land", fmod(p, 1.0), 0.0))
		var pose := _pose(c, fmod(p, 1.0), dy)
		for b in ROT_BONES:
			a.rotation_track_insert_key(tracks[b], time, Quaternion.from_euler(pose[b]))
		a.position_track_insert_key(hips, time, rest_hips + Vector3(0.0, pose["hips_dy"], 0.0))
		a.position_track_insert_key(head, time, rest_head + Vector3(0.0, pose["head_dy"], 0.0))
	return a


## Gait phase, 0 = left heel strike. The left leg is at full forward extension at phase 0 and its
## knee flexes hardest a quarter-cycle later, mid-swing (phase 0.75), while the foot is clear of the
## ground. Flexing at the forward extreme instead reads as a high-knee march, and a form that depends
## only on the thigh angle bends both knees together at the passing pose, where a real gait has one
## straight stance leg.
func _leg_pose(c: Dictionary, p: float) -> Array:
	var thigh: float = c["thigh"]
	var base: float = c["knee_base"]
	var amp: float = c["knee"]
	var lf := pow(maxf(0.0, 0.5 + 0.5 * cos(TAU * (p - 0.75))), 1.5)  # left knee flex, 0..1
	var rf := pow(maxf(0.0, 0.5 - 0.5 * cos(TAU * (p - 0.75))), 1.5)  # right leg is half a cycle off
	return [-thigh * cos(TAU * p), base + amp * lf, thigh * cos(TAU * p), base + amp * rf]


func _pose(c: Dictionary, p: float, dy: float) -> Dictionary:
	var kind: String = c["kind"]
	if kind != "gait":
		return _air_pose(kind, p, dy)
	var ph := TAU * p
	var cosf := cos(ph)  # +1 = left leg forward, right leg back
	var sinf := sin(ph)
	var idle: bool = float(c["thigh"]) == 0.0
	var arm: float = c["arm"]
	var lean: float = c["lean"]
	var yaw: float = c["yaw"]
	var elbow: float = c["elbow"]
	var eswing: float = c["elbow_swing"]
	var sh: float = c["shoulder"]
	var splay: float = c["splay"]
	var legs := _leg_pose(c, p)
	var pose := {}
	pose["Torso"] = Vector3((lean * sinf if idle else lean + lean * 0.15 * sin(2.0 * ph)) * D2R,
		(0.0 if idle else yaw * cosf) * D2R, (1.4 * sinf if idle else 0.8 * cosf) * D2R)
	pose["Head"] = Vector3((-lean * sinf if idle else -lean * 0.7) * D2R,
		(0.0 if idle else -yaw * 0.5 * cosf) * D2R, 0.0)
	# Shoulder rolls the whole arm a couple of degrees; the upper arm pivot is the real joint.
	pose["Shoulder.L"] = Vector3(0.0, 0.0, (0.0 if idle else sh * cosf))
	pose["Shoulder.R"] = Vector3(0.0, 0.0, (0.0 if idle else -sh * cosf))
	# Contralateral and at the same extremes as the legs: left arm back while the left leg is forward.
	# Splay holds the arm clear of the torso: the shoulder sits inside the torso's own width, so a
	# bent elbow would otherwise push the hand through the chest.
	pose["UpperArm.L"] = Vector3(arm * cosf * D2R, 0.0, splay * D2R)
	pose["UpperArm.R"] = Vector3(-arm * cosf * D2R, 0.0, -splay * D2R)
	# Elbow: a held base flexion plus a swing that peaks as that arm swings forward (phase 0.5 for
	# the left arm). Never negative, so the forearm cannot hyperextend.
	var fl := pow(0.5 - 0.5 * cosf, 2.0)
	var fr := pow(0.5 + 0.5 * cosf, 2.0)
	pose["Forearm.L"] = Vector3(-(elbow + eswing * fl) * D2R, 0.0, 0.0)
	pose["Forearm.R"] = Vector3(-(elbow + eswing * fr) * D2R, 0.0, 0.0)
	pose["Hand.L"] = Vector3(-0.15 * (elbow + eswing * fl) * D2R, 0.0, 0.0)
	pose["Hand.R"] = Vector3(-0.15 * (elbow + eswing * fr) * D2R, 0.0, 0.0)
	pose["Thigh.L"] = Vector3(legs[0] * D2R, 0.0, 0.0)
	pose["LowerLeg.L"] = Vector3(legs[1] * D2R, 0.0, 0.0)
	pose["Thigh.R"] = Vector3(legs[2] * D2R, 0.0, 0.0)
	pose["LowerLeg.R"] = Vector3(legs[3] * D2R, 0.0, 0.0)
	pose["hips_dy"] = dy
	pose["head_dy"] = 0.005 * sin(2.0 * ph) if idle else 0.0
	return pose


## Crouch amount for the landing pose at phase q: full depth, with a small settle so the loop
## breathes instead of freezing dead still.
func _land_crouch(q: float) -> float:
	return 1.0 - 0.05 * (0.5 - 0.5 * cos(TAU * q))


## Non-ground clips use the same expanded controls. JUMP extends through launch, FALL holds a
## compact aerodynamic pose, and LAND compresses into the superhero crouch before easing upright.
func _air_pose(kind: String, p: float, dy: float) -> Dictionary:
	var q := clampf(p, 0.0, 1.0)
	var pose := {}
	for b in ROT_BONES:
		pose[b] = Vector3.ZERO
	pose["hips_dy"] = dy
	pose["head_dy"] = 0.0
	if kind == "jump":
		# Launch: legs straight and driving back, arms thrown up and forward, chest open. Held, so a
		# long super-jump rise keeps the launch pose instead of sagging back to idle.
		var ease := 1.0  # held launch pose; the crossfade supplies the snap
		pose["Torso"] = Vector3(-7.0 * D2R * ease, 0.0, 0.0)
		pose["Head"] = Vector3(6.0 * D2R * ease, 0.0, 0.0)
		pose["UpperArm.L"] = Vector3(-72.0 * D2R * ease, 0.0, 14.0 * D2R)
		pose["UpperArm.R"] = Vector3(-72.0 * D2R * ease, 0.0, -14.0 * D2R)
		pose["Forearm.L"] = Vector3(-16.0 * D2R * ease, 0.0, 0.0)
		pose["Forearm.R"] = Vector3(-16.0 * D2R * ease, 0.0, 0.0)
		pose["Hand.L"] = Vector3(-10.0 * D2R * ease, 0.0, 0.0)
		pose["Hand.R"] = Vector3(-10.0 * D2R * ease, 0.0, 0.0)
		pose["Thigh.L"] = Vector3(7.0 * D2R * ease, 0.0, 0.0)
		pose["Thigh.R"] = Vector3(7.0 * D2R * ease, 0.0, 0.0)
		pose["LowerLeg.L"] = Vector3(-3.0 * D2R * ease, 0.0, 0.0)
		pose["LowerLeg.R"] = Vector3(-3.0 * D2R * ease, 0.0, 0.0)
	elif kind == "fall":
		var breathe := sin(TAU * q)
		pose["Torso"] = Vector3(10.0 * D2R, 0.0, 2.0 * D2R * breathe)
		pose["Head"] = Vector3(-5.0 * D2R, 0.0, 0.0)
		pose["UpperArm.L"] = Vector3(35.0 * D2R, 0.0, 24.0 * D2R)
		pose["UpperArm.R"] = Vector3(35.0 * D2R, 0.0, -24.0 * D2R)
		pose["Forearm.L"] = Vector3(-22.0 * D2R, 0.0, 0.0)
		pose["Forearm.R"] = Vector3(-22.0 * D2R, 0.0, 0.0)
		pose["Hand.L"] = Vector3(-5.0 * D2R, 0.0, 0.0)
		pose["Hand.R"] = Vector3(-5.0 * D2R, 0.0, 0.0)
		pose["Thigh.L"] = Vector3(18.0 * D2R, 0.0, 0.0)
		pose["Thigh.R"] = Vector3(18.0 * D2R, 0.0, 0.0)
		pose["LowerLeg.L"] = Vector3(28.0 * D2R, 0.0, 0.0)
		pose["LowerLeg.R"] = Vector3(28.0 * D2R, 0.0, 0.0)
	else:  # land: asymmetric superhero landing, held for as long as LAND lasts
		# Held, not one-shot: see the CLIPS note. The way back up is the crossfade into idle/walk
		# when the controller leaves LAND.
		var crouch := _land_crouch(q)
		var k := crouch * D2R
		pose["Torso"] = Vector3(LAND_LEAN * k, 0.0, 4.0 * k)  # pitched forward, rolled into the planted hand
		pose["Head"] = Vector3(LAND_HEAD * k, 6.0 * k, 0.0)  # lifted, turned a little toward the open arm
		# Support side (.L): thigh forward and out, knee folded deep, foot flat under the hip.
		pose["Thigh.L"] = Vector3(LAND_SUPPORT_THIGH * k, 0.0, LAND_SUPPORT_SPLAY * k)
		pose["LowerLeg.L"] = Vector3(LAND_SUPPORT_KNEE * k, 0.0, 0.0)
		pose["Hand.L"] = Vector3(8.0 * k, 0.0, 0.0)
		# Wide side (.R): thigh thrown out to the side, knee soft, shin angled down to the foot.
		pose["Thigh.R"] = Vector3(LAND_WIDE_THIGH * k, 0.0, LAND_WIDE_SPLAY * k)
		pose["LowerLeg.R"] = Vector3(LAND_WIDE_KNEE * k, 0.0, 0.0)
		pose["Hand.R"] = Vector3(30.0 * k, 0.0, 0.0)  # wrist cocked back: palm down on the street
		# Arms are deliberately asymmetric: .R braces on the ground, .L is thrown out horizontally.
		pose["UpperArm.R"] = Vector3(LAND_PLANT_ARM * k, 0.0, -10.0 * k)
		pose["Forearm.R"] = Vector3(LAND_PLANT_ELBOW * k, 0.0, 0.0)
		pose["UpperArm.L"] = Vector3(-10.0 * k, 0.0, LAND_OPEN_ARM * k)
		pose["Forearm.L"] = Vector3(LAND_OPEN_ELBOW * k, 0.0, 0.0)
	return pose


func _lowest_y(legs: Array) -> float:
	_sk.reset_bone_poses()
	_sk.set_bone_pose_rotation(_sk.find_bone("Thigh.L"), Quaternion(Vector3.RIGHT, legs[0] * D2R))
	_sk.set_bone_pose_rotation(_sk.find_bone("LowerLeg.L"), Quaternion(Vector3.RIGHT, legs[1] * D2R))
	_sk.set_bone_pose_rotation(_sk.find_bone("Thigh.R"), Quaternion(Vector3.RIGHT, legs[2] * D2R))
	_sk.set_bone_pose_rotation(_sk.find_bone("LowerLeg.R"), Quaternion(Vector3.RIGHT, legs[3] * D2R))
	var lo := 1e9
	for p in _skinned(_sk, _mi, true):
		lo = minf(lo, p.y)
	_sk.reset_bone_poses()
	return lo

## Lowest skinned y with every rotation in `pose` applied, hips at their rest height.
func _lowest_y_pose(pose: Dictionary) -> float:
	_sk.reset_bone_poses()
	for b in ROT_BONES:
		_sk.set_bone_pose_rotation(_sk.find_bone(b), Quaternion.from_euler(pose[b]))
	var lo := 1e9
	for p in _skinned(_sk, _mi, true):
		lo = minf(lo, p.y)
	_sk.reset_bone_poses()
	return lo


func _report(rig: Node3D) -> void:
	for i in _sk.get_bone_count():
		var p := _sk.get_bone_parent(i)
		var b := _sk.get_bone_global_rest(i)
		print("BONE %2d %-12s parent %-12s pos (%.3f, %.3f, %.3f)" % [i, _sk.get_bone_name(i),
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

func _bounds() -> AABB:
	var pts := _skinned(_sk, _mi)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for p in pts:
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
