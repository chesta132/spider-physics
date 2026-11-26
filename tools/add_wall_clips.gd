extends SceneTree
## Author the wall-traversal clips into the rig's "moves" library: wall_crawl, wall_jump,
## wall_edge_up, wall_edge_down. Same shape as tools/add_swing_clips.gd: one Animation per clip,
## saved under assets/player_lego/anim/ and registered in player_rig.tscn.
## WALL RUN needs no clip of its own: the pose is RUN's, the controller only re-aims the body.
## Keys sit only on pose beats; a bone a clip never moves gets one rest key, or the pose of whatever
## clip played last leaks into it. Every clip loops: the mixer resets a non-looping clip to the rest
## pose the moment it ends, and each of these is entered for a fixed window by the controller.
## Re-run: godot --headless -s tools/add_wall_clips.gd
const RIG := "res://assets/player_lego/player_rig.tscn"
const DIR := "res://assets/player_lego/anim/"
const D2R := PI / 180.0
const BONES := ["Torso", "Head", "Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "Forearm.L",
	"Forearm.R", "Hand.L", "Hand.R", "Thigh.L", "Thigh.R", "LowerLeg.L", "LowerLeg.R"]

## The rig is authored upright and facing +Z, so every pose here is body space: the controller aims
## the body at the face (chest in for the crawl, feet planted for the run) and the clip never knows
## which way is down. Clips are posed relative to that, so they read the same on a tilted face.
##
## WALL CRAWL: clinging chest-first, contralateral hand/foot pairs alternating. Two beats, mirrored.
## WALL JUMP: compress against the face, kick the legs straight out, then tuck into the air.
## WALL EDGE UP: grip the ledge, press the chest over it, knee onto the roof, stand.
## WALL EDGE DOWN: braced at the edge, swing a leg over, absorb on the surface below.
const CLIPS := [
	{"name": "wall_crawl", "len": 0.9, "keys": [
		[0.0, {"Torso": Vector3(10, 0, 6), "Head": Vector3(-10, 0, -4),
			"Shoulder.L": Vector3(0, 0, 8), "Shoulder.R": Vector3(0, 0, -4),
			"UpperArm.L": Vector3(-152, 0, 16), "Forearm.L": Vector3(-20, 0, 0), "Hand.L": Vector3(-12, 0, 0),
			"UpperArm.R": Vector3(-48, 0, -16), "Forearm.R": Vector3(-92, 0, 0), "Hand.R": Vector3(-18, 0, 0),
			"Thigh.L": Vector3(16, 0, 8), "LowerLeg.L": Vector3(20, 0, 0),
			"Thigh.R": Vector3(-26, 0, -10), "LowerLeg.R": Vector3(72, 0, 0)}],
		[0.45, {"Torso": Vector3(10, 0, -6), "Head": Vector3(-10, 0, 4),
			"Shoulder.L": Vector3(0, 0, 4), "Shoulder.R": Vector3(0, 0, -8),
			"UpperArm.L": Vector3(-48, 0, 16), "Forearm.L": Vector3(-92, 0, 0), "Hand.L": Vector3(-18, 0, 0),
			"UpperArm.R": Vector3(-152, 0, -16), "Forearm.R": Vector3(-20, 0, 0), "Hand.R": Vector3(-12, 0, 0),
			"Thigh.L": Vector3(-26, 0, 10), "LowerLeg.L": Vector3(72, 0, 0),
			"Thigh.R": Vector3(16, 0, -8), "LowerLeg.R": Vector3(20, 0, 0)}]]},
	{"name": "wall_jump", "len": 0.5, "keys": [
		[0.0, {"Torso": Vector3(14, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperArm.L": Vector3(-34, 0, 24), "UpperArm.R": Vector3(-34, 0, -24),
			"Forearm.L": Vector3(-72, 0, 0), "Forearm.R": Vector3(-72, 0, 0),
			"Thigh.L": Vector3(-36, 0, 4), "LowerLeg.L": Vector3(80, 0, 0),
			"Thigh.R": Vector3(-22, 0, -4), "LowerLeg.R": Vector3(64, 0, 0)}],
		[0.1, {"Torso": Vector3(-10, 0, 0), "Head": Vector3(8, 0, 0),
			"UpperArm.L": Vector3(34, 0, 42), "UpperArm.R": Vector3(34, 0, -42),
			"Forearm.L": Vector3(-10, 0, 0), "Forearm.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(12, 0, 2), "LowerLeg.L": Vector3(2, 0, 0),
			"Thigh.R": Vector3(18, 0, -2), "LowerLeg.R": Vector3(0, 0, 0)}],
		[0.32, {"Torso": Vector3(-4, 0, 0), "Head": Vector3(4, 0, 0),
			"UpperArm.L": Vector3(44, 0, 34), "UpperArm.R": Vector3(44, 0, -34),
			"Forearm.L": Vector3(-22, 0, 0), "Forearm.R": Vector3(-22, 0, 0),
			"Thigh.L": Vector3(-20, 0, 0), "LowerLeg.L": Vector3(36, 0, 0),
			"Thigh.R": Vector3(10, 0, 0), "LowerLeg.R": Vector3(18, 0, 0)}]]},
	{"name": "wall_edge_up", "len": 0.75, "keys": [
		[0.0, {"Torso": Vector3(8, 0, 0), "Head": Vector3(-18, 0, 0),
			"UpperArm.L": Vector3(-168, 0, 12), "UpperArm.R": Vector3(-168, 0, -12),
			"Forearm.L": Vector3(-18, 0, 0), "Forearm.R": Vector3(-18, 0, 0),
			"Hand.L": Vector3(-10, 0, 0), "Hand.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-20, 0, 8), "LowerLeg.L": Vector3(62, 0, 0),
			"Thigh.R": Vector3(-6, 0, -8), "LowerLeg.R": Vector3(40, 0, 0)}],
		[0.18, {"Torso": Vector3(26, 0, 0), "Head": Vector3(-22, 0, 0),
			"UpperArm.L": Vector3(-118, 0, 20), "UpperArm.R": Vector3(-118, 0, -20),
			"Forearm.L": Vector3(-78, 0, 0), "Forearm.R": Vector3(-78, 0, 0),
			"Thigh.L": Vector3(-46, 0, 6), "LowerLeg.L": Vector3(96, 0, 0),
			"Thigh.R": Vector3(-30, 0, -6), "LowerLeg.R": Vector3(84, 0, 0)}],
		[0.38, {"Torso": Vector3(14, 0, 4), "Head": Vector3(-10, 0, 0),
			"UpperArm.L": Vector3(-32, 0, 30), "UpperArm.R": Vector3(-32, 0, -30),
			"Forearm.L": Vector3(-28, 0, 0), "Forearm.R": Vector3(-28, 0, 0),
			"Thigh.L": Vector3(-72, 0, 10), "LowerLeg.L": Vector3(102, 0, 0),
			"Thigh.R": Vector3(4, 0, -6), "LowerLeg.R": Vector3(18, 0, 0)}],
		[0.6, {"Torso": Vector3(4, 0, 0), "Head": Vector3(-2, 0, 0),
			"UpperArm.L": Vector3(-6, 0, 10), "UpperArm.R": Vector3(-6, 0, -10),
			"Forearm.L": Vector3(-10, 0, 0), "Forearm.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-6, 0, 0), "LowerLeg.L": Vector3(10, 0, 0),
			"Thigh.R": Vector3(4, 0, 0), "LowerLeg.R": Vector3(6, 0, 0)}]]},
	{"name": "wall_edge_down", "len": 0.5, "keys": [
		[0.0, {"Torso": Vector3(18, 0, 0), "Head": Vector3(-14, 0, 0),
			"UpperArm.L": Vector3(-20, 0, 34), "UpperArm.R": Vector3(-20, 0, -34),
			"Forearm.L": Vector3(-46, 0, 0), "Forearm.R": Vector3(-46, 0, 0),
			"Thigh.L": Vector3(-30, 0, 6), "LowerLeg.L": Vector3(70, 0, 0),
			"Thigh.R": Vector3(-22, 0, -6), "LowerLeg.R": Vector3(58, 0, 0)}],
		[0.14, {"Torso": Vector3(10, 0, 0), "Head": Vector3(-6, 0, 0),
			"UpperArm.L": Vector3(8, 0, 48), "UpperArm.R": Vector3(8, 0, -48),
			"Forearm.L": Vector3(-16, 0, 0), "Forearm.R": Vector3(-16, 0, 0),
			"Thigh.L": Vector3(24, 0, 4), "LowerLeg.L": Vector3(14, 0, 0),
			"Thigh.R": Vector3(-36, 0, -4), "LowerLeg.R": Vector3(44, 0, 0)}],
		[0.36, {"Torso": Vector3(22, 0, 0), "Head": Vector3(-16, 0, 0),
			"UpperArm.L": Vector3(-26, 0, 22), "UpperArm.R": Vector3(-26, 0, -22),
			"Forearm.L": Vector3(-34, 0, 0), "Forearm.R": Vector3(-34, 0, 0),
			"Thigh.L": Vector3(-28, 0, 6), "LowerLeg.L": Vector3(64, 0, 0),
			"Thigh.R": Vector3(-24, 0, -6), "LowerLeg.R": Vector3(60, 0, 0)}]]},
]

var _sk: Skeleton3D


func _initialize() -> void:
	var rig := (load(RIG) as PackedScene).instantiate()
	_sk = rig.find_child("Skeleton", true, false) as Skeleton3D
	DirAccess.make_dir_recursive_absolute(DIR)
	var ok := true
	for c in CLIPS:
		var a := _clip(c)
		var path: String = DIR + c["name"] + ".tres"
		var err := ResourceSaver.save(a, path)
		ok = ok and err == OK
		print("CLIP %-14s len %.2f s keys %d tracks %d loop %d -> %s" % [
			c["name"], a.length, _keys(a), a.get_track_count(), a.loop_mode, path])
	rig.free()
	print("RESULT ", "saved" if ok else "FAILED")
	quit(0 if ok else 1)


func _keys(a: Animation) -> int:
	var n := 0
	for t in a.get_track_count():
		n += a.track_get_key_count(t)
	return n


func _clip(c: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = c["len"]
	a.loop_mode = Animation.LOOP_LINEAR
	var times: Array = []
	for k in c["keys"]:
		times.append(k[0])
	times.append(float(c["len"]))  # loop closes on the first pose
	var tracks := {}
	for b in BONES:
		tracks[b] = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tracks[b], "Skeleton:" + b)
	var hips := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hips, "Skeleton:Hips")
	var head := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(head, "Skeleton:Head")
	a.position_track_insert_key(hips, 0.0, _sk.get_bone_rest(_sk.find_bone("Hips")).origin)
	a.position_track_insert_key(head, 0.0, _sk.get_bone_rest(_sk.find_bone("Head")).origin)
	for b in BONES:
		var moved := false
		for k in c["keys"]:
			if (k[1] as Dictionary).has(b):
				moved = true
				break
		if not moved:
			a.rotation_track_insert_key(tracks[b], 0.0, Quaternion.IDENTITY)  # rest, not last clip's pose
			continue
		for i in times.size():
			var pose: Dictionary = c["keys"][i % c["keys"].size()][1] if i < c["keys"].size() else c["keys"][0][1]
			var deg: Vector3 = pose.get(b, Vector3.ZERO)
			a.rotation_track_insert_key(tracks[b], times[i], Quaternion.from_euler(deg * D2R))
	return a
