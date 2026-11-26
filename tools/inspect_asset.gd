extends SceneTree
## Author the web-movement clips into the rig's "moves" library: swing_up / swing_down for one and
## two webs, swing_jump and zip. One Animation per clip, saved under assets/player_lego/anim/ and
## registered in player_rig.tscn, so the generator never has to re-bake the mesh for a pose tweak.
## Keys sit only on pose beats (2-3 per clip). A bone the clip never moves still gets one rest key,
## or the pose of whatever clip played last leaks into it.
## Re-run: godot --headless -s tools/add_swing_clips.gd
const RIG := "res://assets/player_lego/player_rig.tscn"
const DIR := "res://assets/player_lego/anim/"
const D2R := PI / 180.0
const BONES := ["Torso", "Head", "Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "Forearm.L",
	"Forearm.R", "Hand.L", "Hand.R", "Thigh.L", "Thigh.R", "LowerLeg.L", "LowerLeg.R"]

## SWING UP: arms up toward the web, chest open, legs trailing and scissoring. 1 web = both hands
## stacked over one line; 2 webs = the same reach split wide so each hand owns its own line.
## SWING DOWN: the trough. Same arms, but looser: elbows give, torso extends, legs hang and swing.
## SWING JUMP: the release beat. Web-side arm trails up behind the body, free arm reaches forward,
## knees tuck: nothing like the symmetric JUMP launch.
## ZIP: streamlined tuck, leading arm out along the pull, trailing arm back, knees up.
const CLIPS := [
	{"name": "swing_up_1", "len": 0.7, "keys": [
		[0.0, {"Torso": Vector3(8, 0, 3), "Head": Vector3(-14, 0, 0),
			"Shoulder.L": Vector3(0, 0, 6), "Shoulder.R": Vector3(0, 0, -6),
			"UpperArm.L": Vector3(-150, 0, 10), "UpperArm.R": Vector3(-150, 0, -10),
			"Forearm.L": Vector3(-16, 0, 0), "Forearm.R": Vector3(-16, 0, 0),
			"Hand.L": Vector3(-10, 0, 0), "Hand.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-18, 0, 0), "LowerLeg.L": Vector3(38, 0, 0),
			"Thigh.R": Vector3(18, 0, 0), "LowerLeg.R": Vector3(52, 0, 0)}],
		[0.35, {"Torso": Vector3(6, 0, -3), "Head": Vector3(-12, 0, 0),
			"UpperArm.L": Vector3(-146, 0, 10), "UpperArm.R": Vector3(-146, 0, -10),
			"Forearm.L": Vector3(-22, 0, 0), "Forearm.R": Vector3(-22, 0, 0),
			"Thigh.L": Vector3(18, 0, 0), "LowerLeg.L": Vector3(52, 0, 0),
			"Thigh.R": Vector3(-18, 0, 0), "LowerLeg.R": Vector3(38, 0, 0)}]]},
	{"name": "swing_up_2", "len": 0.7, "keys": [
		[0.0, {"Torso": Vector3(6, 0, 5), "Head": Vector3(-12, 0, 0),
			"Shoulder.L": Vector3(0, 0, 10), "Shoulder.R": Vector3(0, 0, -10),
			"UpperArm.L": Vector3(-140, 0, 38), "UpperArm.R": Vector3(-140, 0, -38),
			"Forearm.L": Vector3(-22, 0, 0), "Forearm.R": Vector3(-22, 0, 0),
			"Hand.L": Vector3(-10, 0, 0), "Hand.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-18, 0, 0), "LowerLeg.L": Vector3(38, 0, 0),
			"Thigh.R": Vector3(18, 0, 0), "LowerLeg.R": Vector3(52, 0, 0)}],
		[0.35, {"Torso": Vector3(4, 0, -5), "Head": Vector3(-10, 0, 0),
			"UpperArm.L": Vector3(-134, 0, 44), "UpperArm.R": Vector3(-134, 0, -44),
			"Forearm.L": Vector3(-28, 0, 0), "Forearm.R": Vector3(-28, 0, 0),
			"Thigh.L": Vector3(18, 0, 0), "LowerLeg.L": Vector3(52, 0, 0),
			"Thigh.R": Vector3(-18, 0, 0), "LowerLeg.R": Vector3(38, 0, 0)}]]},
	{"name": "swing_down_1", "len": 0.8, "keys": [
		[0.0, {"Torso": Vector3(-5, 0, 2), "Head": Vector3(-2, 0, 0),
			"Shoulder.L": Vector3(0, 0, 3), "Shoulder.R": Vector3(0, 0, -3),
			"UpperArm.L": Vector3(-156, 0, 12), "UpperArm.R": Vector3(-156, 0, -12),
			"Forearm.L": Vector3(-34, 0, 0), "Forearm.R": Vector3(-34, 0, 0),
			"Hand.L": Vector3(-4, 0, 0), "Hand.R": Vector3(-4, 0, 0),
			"Thigh.L": Vector3(24, 0, 0), "LowerLeg.L": Vector3(58, 0, 0),
			"Thigh.R": Vector3(6, 0, 0), "LowerLeg.R": Vector3(40, 0, 0)}],
		[0.4, {"Torso": Vector3(-9, 0, -2), "Head": Vector3(2, 0, 0),
			"UpperArm.L": Vector3(-148, 0, 12), "UpperArm.R": Vector3(-148, 0, -12),
			"Forearm.L": Vector3(-42, 0, 0), "Forearm.R": Vector3(-42, 0, 0),
			"Thigh.L": Vector3(6, 0, 0), "LowerLeg.L": Vector3(40, 0, 0),
			"Thigh.R": Vector3(26, 0, 0), "LowerLeg.R": Vector3(62, 0, 0)}]]},
	{"name": "swing_down_2", "len": 0.8, "keys": [
		[0.0, {"Torso": Vector3(-6, 0, 5), "Head": Vector3(0, 0, 0),
			"Shoulder.L": Vector3(0, 0, 8), "Shoulder.R": Vector3(0, 0, -8),
			"UpperArm.L": Vector3(-116, 0, 48), "UpperArm.R": Vector3(-116, 0, -48),
			"Forearm.L": Vector3(-28, 0, 0), "Forearm.R": Vector3(-28, 0, 0),
			"Hand.L": Vector3(0, 0, 0), "Hand.R": Vector3(0, 0, 0),
			"Thigh.L": Vector3(22, 0, 0), "LowerLeg.L": Vector3(56, 0, 0),
			"Thigh.R": Vector3(4, 0, 0), "LowerLeg.R": Vector3(38, 0, 0)}],
		[0.4, {"Torso": Vector3(-10, 0, -5), "Head": Vector3(4, 0, 0),
			"UpperArm.L": Vector3(-110, 0, 46), "UpperArm.R": Vector3(-110, 0, -46),
			"Forearm.L": Vector3(-36, 0, 0), "Forearm.R": Vector3(-36, 0, 0),
			"Thigh.L": Vector3(4, 0, 0), "LowerLeg.L": Vector3(38, 0, 0),
			"Thigh.R": Vector3(24, 0, 0), "LowerLeg.R": Vector3(60, 0, 0)}]]},
	{"name": "swing_jump", "len": 0.6, "loop_from": 0.4,
		# Launch pose held for 0.2 s, blends into the clip below by 0.4 s, which then loops. Godot can't loop part of a clip, so
		# the clip itself is LOOP_NONE and player_controller.gd restarts it at loop_from.
		"intro": [0.2, {"Torso": Vector3(42, 0, 0), "Head": Vector3(-18, 0, 0),
			"UpperArm.L": Vector3(-48, 0, -8), "UpperArm.R": Vector3(-48, 0, 8),
			"Forearm.L": Vector3(-22, 0, -8), "Forearm.R": Vector3(-22, 0, 8),
			"Hand.L": Vector3(-8, 0, 0), "Hand.R": Vector3(-8, 0, 0),
			"Thigh.L": Vector3(-10, 0, 68), "LowerLeg.L": Vector3(20, 0, -12),
			"Thigh.R": Vector3(-30, 0, -62), "LowerLeg.R": Vector3(55, 0, 50)}],
		"keys": [
		[0.0, {"Torso": Vector3(-10, 0, 8), "Head": Vector3(6, 0, -4),
			"Shoulder.L": Vector3(0, 0, 8), "Shoulder.R": Vector3(0, 0, -4),
			"UpperArm.L": Vector3(-168, 0, 20), "UpperArm.R": Vector3(-40, 0, -34),
			"Forearm.L": Vector3(-34, 0, 0), "Forearm.R": Vector3(-26, 0, 0),
			"Hand.L": Vector3(-14, 0, 0), "Hand.R": Vector3(-8, 0, 0),
			"Thigh.L": Vector3(-48, 0, 6), "LowerLeg.L": Vector3(88, 0, 0),
			"Thigh.R": Vector3(-14, 0, 0), "LowerLeg.R": Vector3(40, 0, 0)}],
		[0.3, {"Torso": Vector3(-6, 0, 6), "Head": Vector3(4, 0, -3),
			"UpperArm.L": Vector3(-158, 0, 18), "UpperArm.R": Vector3(-46, 0, -30),
			"Forearm.L": Vector3(-42, 0, 0), "Forearm.R": Vector3(-20, 0, 0),
			"Thigh.L": Vector3(-40, 0, 4), "LowerLeg.L": Vector3(80, 0, 0),
			"Thigh.R": Vector3(-20, 0, 0), "LowerLeg.R": Vector3(48, 0, 0)}]]},
	{"name": "zip", "len": 0.5, "keys": [
		[0.0, {"Torso": Vector3(20, 0, 0), "Head": Vector3(-24, 0, 0),
			"Shoulder.R": Vector3(0, 0, -6),
			"UpperArm.R": Vector3(-96, 0, -6), "Forearm.R": Vector3(-12, 0, 0), "Hand.R": Vector3(-6, 0, 0),
			"UpperArm.L": Vector3(48, 0, 14), "Forearm.L": Vector3(-18, 0, 0),
			"Thigh.L": Vector3(-38, 0, 0), "LowerLeg.L": Vector3(78, 0, 0),
			"Thigh.R": Vector3(-22, 0, 0), "LowerLeg.R": Vector3(62, 0, 0)}],
		[0.25, {"Torso": Vector3(16, 0, 0), "Head": Vector3(-20, 0, 0),
			"UpperArm.R": Vector3(-90, 0, -6),
			"Thigh.L": Vector3(-32, 0, 0), "LowerLeg.L": Vector3(70, 0, 0),
			"Thigh.R": Vector3(-26, 0, 0), "LowerLeg.R": Vector3(66, 0, 0)}]]},
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
		print("CLIP %-12s len %.2f s keys %d tracks %d loop %d -> %s" % [
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
	var lead: float = c.get("loop_from", 0.0)  # loop keys start here (after an intro pose)
	var intro: Array = c.get("intro", [])
	a.length = lead + c["len"]
	a.loop_mode = Animation.LOOP_NONE if not intro.is_empty() else Animation.LOOP_LINEAR
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
		if not intro.is_empty() and (intro[1] as Dictionary).has(b):
			moved = true
		if not moved:
			a.rotation_track_insert_key(tracks[b], 0.0, Quaternion.IDENTITY)  # rest, not last clip's pose
			continue
		if not intro.is_empty():
			var ipose: Vector3 = (intro[1] as Dictionary).get(b, Vector3.ZERO)
			var iq := Quaternion.from_euler(ipose * D2R)
			a.rotation_track_insert_key(tracks[b], 0.0, iq)
			a.rotation_track_insert_key(tracks[b], float(intro[0]), iq)
		for i in times.size():
			var t: float = lead + times[i]
			var pose: Dictionary = c["keys"][i % c["keys"].size()][1] if i < c["keys"].size() else c["keys"][0][1]
			var deg: Vector3 = pose.get(b, Vector3.ZERO)
			a.rotation_track_insert_key(tracks[b], t, Quaternion.from_euler(deg * D2R))
	return a
