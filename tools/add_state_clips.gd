extends SceneTree
## Author the charge / launch / air / perch clips into the rig's "moves" library: charge, super_jump,
## dive, fast_dive, dev_fly, watching. Same shape as tools/add_wall_clips.gd: one Animation per clip,
## saved under assets/player_lego/anim/ and registered in player_rig.tscn.
## Every clip loops (the mixer resets a non-looping clip to the rest pose the moment it ends) and
## closes on its own first pose, so a held state can hold for as long as it likes.
## Re-run: godot --headless -s tools/add_state_clips.gd
const RIG := "res://assets/player_lego/player_rig.tscn"
const DIR := "res://assets/player_lego/anim/"
const D2R := PI / 180.0
const BONES := ["Torso", "Head", "Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R", "Forearm.L",
	"Forearm.R", "Hand.L", "Hand.R", "Thigh.L", "Thigh.R", "LowerLeg.L", "LowerLeg.R"]

## Body space, model facing +Z: thigh X negative swings the knee forward, LowerLeg X positive folds
## the knee, UpperArm X negative lifts the arm forward/up, Z splays it out (.L positive, .R negative),
## Forearm X negative bends the elbow, Torso X positive pitches the chest forward.
##
## CHARGE: loaded spring. Deep crouch, arms pulled back, and a slow settle deeper into the squat with
## a hint of tremble (roll) so the hold is not dead still.
## SUPER JUMP: the same loaded pose releasing: one compressed beat, the arms whipping through the
## front (a direct coil->overhead key is over 180 deg, and the mixer takes the short way round), hard
## leg extension, then a stretched flight pose.
## DIVE: head-first, streamlined: chest pitched over, arms swept back along the body, legs straight
## and together.
## FAST DIVE: the same shape, tighter: chest pitched further, arms fully back, legs locked straight.
## DEV FLY: neutral superman glide, one arm reaching, one trailing, minimal.
## WATCHING: rooftop crouch: planted foot flat, knee raised with a forearm on it, other hand on the
## ledge, torso leaned forward, head down over the city, breathing only.
const CLIPS := [
	{"name": "charge", "len": 1.0, "keys": [
		[0.0, {"Torso": Vector3(34, 0, 0), "Head": Vector3(-30, 0, 0),
			"UpperArm.L": Vector3(46, 0, 16), "UpperArm.R": Vector3(46, 0, -16),
			"Forearm.L": Vector3(-26, 0, 0), "Forearm.R": Vector3(-26, 0, 0),
			"Hand.L": Vector3(-10, 0, 0), "Hand.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-62, 0, 4), "LowerLeg.L": Vector3(104, 0, 0),
			"Thigh.R": Vector3(-58, 0, -4), "LowerLeg.R": Vector3(98, 0, 0)}],
		[0.5, {"Torso": Vector3(37, 0, 1.5), "Head": Vector3(-31, 0, -1),
			"UpperArm.L": Vector3(49, 0, 18), "UpperArm.R": Vector3(49, 0, -18),
			"Forearm.L": Vector3(-29, 0, 0), "Forearm.R": Vector3(-29, 0, 0),
			"Hand.L": Vector3(-12, 0, 0), "Hand.R": Vector3(-12, 0, 0),
			"Thigh.L": Vector3(-65, 0, 4), "LowerLeg.L": Vector3(108, 0, 0),
			"Thigh.R": Vector3(-61, 0, -4), "LowerLeg.R": Vector3(102, 0, 0)}]]},
	{"name": "super_jump", "len": 0.5, "keys": [
		[0.0, {"Torso": Vector3(30, 0, 0), "Head": Vector3(-26, 0, 0),
			"Shoulder.L": Vector3(0, 0, 4), "Shoulder.R": Vector3(0, 0, -4),
			"UpperArm.L": Vector3(44, 0, 14), "UpperArm.R": Vector3(44, 0, -14),
			"Forearm.L": Vector3(-24, 0, 0), "Forearm.R": Vector3(-24, 0, 0),
			"Hand.L": Vector3(-10, 0, 0), "Hand.R": Vector3(-10, 0, 0),
			"Thigh.L": Vector3(-58, 0, 4), "LowerLeg.L": Vector3(100, 0, 0),
			"Thigh.R": Vector3(-54, 0, -4), "LowerLeg.R": Vector3(94, 0, 0)}],
		[0.04, {"Torso": Vector3(8, 0, 0), "Head": Vector3(-6, 0, 0),
			"Shoulder.L": Vector3(0, 0, 6), "Shoulder.R": Vector3(0, 0, -6),
			"UpperArm.L": Vector3(-62, 0, 18), "UpperArm.R": Vector3(-62, 0, -18),
			"Forearm.L": Vector3(-40, 0, 0), "Forearm.R": Vector3(-40, 0, 0),
			"Hand.L": Vector3(-8, 0, 0), "Hand.R": Vector3(-8, 0, 0),
			"Thigh.L": Vector3(-30, 0, 3), "LowerLeg.L": Vector3(60, 0, 0),
			"Thigh.R": Vector3(-26, 0, -3), "LowerLeg.R": Vector3(54, 0, 0)}],
		[0.08, {"Torso": Vector3(-14, 0, 0), "Head": Vector3(10, 0, 0),
			"Shoulder.L": Vector3(0, 0, 8), "Shoulder.R": Vector3(0, 0, -8),
			"UpperArm.L": Vector3(-168, 0, 12), "UpperArm.R": Vector3(-168, 0, -12),
			"Forearm.L": Vector3(-8, 0, 0), "Forearm.R": Vector3(-8, 0, 0),
			"Hand.L": Vector3(-4, 0, 0), "Hand.R": Vector3(-4, 0, 0),
			"Thigh.L": Vector3(12, 0, 2), "LowerLeg.L": Vector3(0, 0, 0),
			"Thigh.R": Vector3(14, 0, -2), "LowerLeg.R": Vector3(0, 0, 0)}],
		[0.32, {"Torso": Vector3(-8, 0, 0), "Head": Vector3(6, 0, 0),
			"Shoulder.L": Vector3(0, 0, 6), "Shoulder.R": Vector3(0, 0, -6),
			"UpperArm.L": Vector3(-172, 0, 10), "UpperArm.R": Vector3(-172, 0, -10),
			"Forearm.L": Vector3(-6, 0, 0), "Forearm.R": Vector3(-6, 0, 0),
			"Hand.L": Vector3(-2, 0, 0), "Hand.R": Vector3(-2, 0, 0),
			"Thigh.L": Vector3(6, 0, 2), "LowerLeg.L": Vector3(4, 0, 0),
			"Thigh.R": Vector3(8, 0, -2), "LowerLeg.R": Vector3(2, 0, 0)}]]},
	{"name": "dive", "len": 0.6, "keys": [
		[0.0, {"Torso": Vector3(52, 0, 0), "Head": Vector3(-32, 0, 0),
			"UpperArm.L": Vector3(72, 0, 22), "UpperArm.R": Vector3(72, 0, -22),
			"Forearm.L": Vector3(-6, 0, 0), "Forearm.R": Vector3(-6, 0, 0),
			"Thigh.L": Vector3(8, 0, 2), "LowerLeg.L": Vector3(4, 0, 0),
			"Thigh.R": Vector3(8, 0, -2), "LowerLeg.R": Vector3(4, 0, 0)}],
		[0.3, {"Torso": Vector3(48, 0, 0), "Head": Vector3(-28, 0, 0),
			"UpperArm.L": Vector3(76, 0, 24), "UpperArm.R": Vector3(76, 0, -24),
			"Forearm.L": Vector3(-8, 0, 0), "Forearm.R": Vector3(-8, 0, 0),
			"Thigh.L": Vector3(10, 0, 2), "LowerLeg.L": Vector3(2, 0, 0),
			"Thigh.R": Vector3(10, 0, -2), "LowerLeg.R": Vector3(2, 0, 0)}]]},
	{"name": "fast_dive", "len": 0.4, "keys": [
		[0.0, {"Torso": Vector3(70, 0, 0), "Head": Vector3(-42, 0, 0),
			"UpperArm.L": Vector3(78, 0, 6), "UpperArm.R": Vector3(78, 0, -6),
			"Forearm.L": Vector3(-2, 0, 0), "Forearm.R": Vector3(-2, 0, 0),
			"Thigh.L": Vector3(2, 0, 1), "LowerLeg.L": Vector3(0, 0, 0),
			"Thigh.R": Vector3(2, 0, -1), "LowerLeg.R": Vector3(0, 0, 0)}],
		[0.2, {"Torso": Vector3(68, 0, 0), "Head": Vector3(-40, 0, 0),
			"UpperArm.L": Vector3(80, 0, 5), "UpperArm.R": Vector3(80, 0, -5),
			"Forearm.L": Vector3(-1, 0, 0), "Forearm.R": Vector3(-1, 0, 0),
			"Thigh.L": Vector3(1, 0, 1), "LowerLeg.L": Vector3(0, 0, 0),
			"Thigh.R": Vector3(1, 0, -1), "LowerLeg.R": Vector3(0, 0, 0)}]]},
	{"name": "dev_fly", "len": 1.2, "keys": [
		[0.0, {"Torso": Vector3(58, 0, 0), "Head": Vector3(-34, 0, 0),
			"UpperArm.L": Vector3(-104, 0, 6), "UpperArm.R": Vector3(34, 0, -8),
			"Forearm.L": Vector3(-8, 0, 0), "Forearm.R": Vector3(-6, 0, 0),
			"Thigh.L": Vector3(10, 0, 2), "LowerLeg.L": Vector3(4, 0, 0),
			"Thigh.R": Vector3(8, 0, -2), "LowerLeg.R": Vector3(4, 0, 0)}],
		[0.6, {"Torso": Vector3(54, 0, 0), "Head": Vector3(-30, 0, 0),
			"UpperArm.L": Vector3(-100, 0, 8), "UpperArm.R": Vector3(38, 0, -6),
			"Forearm.L": Vector3(-10, 0, 0), "Forearm.R": Vector3(-4, 0, 0),
			"Thigh.L": Vector3(12, 0, 2), "LowerLeg.L": Vector3(2, 0, 0),
			"Thigh.R": Vector3(6, 0, -2), "LowerLeg.R": Vector3(6, 0, 0)}]]},
	{"name": "watching", "len": 3.0, "keys": [
		[0.0, {"Torso": Vector3(30, 0, 2), "Head": Vector3(-24, 0, 0),
			"Shoulder.L": Vector3(0, 0, 6), "Shoulder.R": Vector3(0, 0, -4),
			"UpperArm.L": Vector3(-62, 0, 34), "Forearm.L": Vector3(-104, 0, 0), "Hand.L": Vector3(-10, 0, 0),
			"UpperArm.R": Vector3(40, 0, -18), "Forearm.R": Vector3(-18, 0, 0), "Hand.R": Vector3(12, 0, 0),
			"Thigh.L": Vector3(-84, 0, 10), "LowerLeg.L": Vector3(116, 0, 0),
			"Thigh.R": Vector3(-46, 0, -18), "LowerLeg.R": Vector3(118, 0, 0)}],
		[1.5, {"Torso": Vector3(31.5, 0, 2), "Head": Vector3(-23, 0, 3),
			"Shoulder.L": Vector3(0, 0, 6), "Shoulder.R": Vector3(0, 0, -4),
			"UpperArm.L": Vector3(-63, 0, 34), "Forearm.L": Vector3(-102, 0, 0), "Hand.L": Vector3(-9, 0, 0),
			"UpperArm.R": Vector3(40, 0, -18), "Forearm.R": Vector3(-18, 0, 0), "Hand.R": Vector3(12, 0, 0),
			"Thigh.L": Vector3(-83, 0, 10), "LowerLeg.L": Vector3(115, 0, 0),
			"Thigh.R": Vector3(-46, 0, -18), "LowerLeg.R": Vector3(118, 0, 0)}]]},
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
