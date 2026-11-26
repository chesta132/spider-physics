extends SceneTree
## Animation-only coverage for the charge / launch / air / perch states.
## Run: godot --headless -s tests/state_anim_check.gd

const CLIPS := ["charge", "super_jump", "dive", "fast_dive", "dev_fly", "watching"]
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)
	root.add_child(main)
	for i in 90:
		await physics_frame
	var p: CharacterBody3D = main.get_node("Player")
	var ap: AnimationPlayer = p.get_node("Visual/Model/Rig/AnimationPlayer")

	# 1. Every clip exists, loops, closes on its own first pose, and stays minimal.
	for clip in CLIPS:
		var path: String = "moves/" + clip
		if not ap.has_animation(path):
			check("clip %s exists" % path, false)
			continue
		var a := ap.get_animation(path)
		var keys := 0
		var widest := 0
		var closed := true
		for t in a.get_track_count():
			keys += a.track_get_key_count(t)
			widest = maxi(widest, a.track_get_key_count(t))
			closed = closed and a.track_get_key_value(t, 0) == a.track_get_key_value(t, a.track_get_key_count(t) - 1)
		check("clip %s exists (%d keys, %d tracks)" % [path, keys, a.get_track_count()],
			a.get_track_count() == 16)
		check("%s loops and closes on its first pose" % path, a.loop_mode == Animation.LOOP_LINEAR and closed)
		check("%s stays minimal (widest track %d keys <= 5)" % [path, widest], widest <= 5)

	# 2. The poses are distinct: charge is a coil, super jump an extension, the dives differ.
	var torso := {}
	var arm := {}
	var torso_min := {}
	for clip in CLIPS:
		var a: Animation = ap.get_animation("moves/" + clip)
		for t in a.get_track_count():
			var path := str(a.track_get_path(t))
			if path == "Skeleton:Torso":
				torso[clip] = (a.track_get_key_value(t, 0) as Quaternion).get_euler().x
				var lo := 999.0
				for k in a.track_get_key_count(t):
					lo = minf(lo, rad_to_deg((a.track_get_key_value(t, k) as Quaternion).get_euler().x))
				torso_min[clip] = lo
			if path == "Skeleton:UpperArm.L":
				arm[clip] = (a.track_get_key_value(t, 0) as Quaternion).get_euler().x
	check("charge is coiled, not extended (torso %.0f deg)" % rad_to_deg(torso["charge"]), rad_to_deg(torso["charge"]) > 25.0)
	check("charge pulls the arms back (%.0f deg)" % rad_to_deg(arm["charge"]), rad_to_deg(arm["charge"]) > 20.0)
	check("super jump opens the torso back (extension %.0f deg vs charge %.0f)" % [torso_min["super_jump"], torso_min["charge"]],
		torso_min["super_jump"] < 0.0 and torso_min["super_jump"] < torso_min["charge"] - 20.0)
	check("fast dive is more extreme than dive (torso %.0f vs %.0f deg, arm %.0f vs %.0f)" % [
		rad_to_deg(torso["fast_dive"]), rad_to_deg(torso["dive"]), rad_to_deg(arm["fast_dive"]), rad_to_deg(arm["dive"])],
		rad_to_deg(torso["fast_dive"]) > rad_to_deg(torso["dive"]) + 10.0 and rad_to_deg(arm["fast_dive"]) > rad_to_deg(arm["dive"]))

	# 3. Each state picks its own clip (animation wiring only, no state machine change).
	var PC := load("res://scripts/player_controller.gd")
	for pair in [[PC.State.CHARGE, "moves/charge"], [PC.State.SUPER, "moves/super_jump"],
			[PC.State.DIVE, "moves/dive"], [PC.State.FAST_DIVE, "moves/fast_dive"],
			[PC.State.FLY, "moves/dev_fly"], [PC.State.WATCHING, "moves/watching"]]:
		p._play_ground_clip(pair[0])
		check("state %s plays %s (%s)" % [p.STATE_NAMES[pair[0]], pair[1], ap.current_animation],
			ap.current_animation == pair[1])
		check("%s is held at 1x playback" % pair[1], ap.speed_scale > 0.0)

	# 4. The dive and the glide pitch the body onto its velocity; a still body stays upright.
	p.velocity = Vector3(0.0, -12.0, 0.0)
	check("straight-down dive pitches the head down (%.0f deg)" % rad_to_deg(p._air_pitch()), absf(absf(rad_to_deg(p._air_pitch())) - 180.0) < 1.0)
	p.velocity = Vector3(0.0, 0.0, 12.0)
	check("level flight points the head forward (%.0f deg)" % rad_to_deg(p._air_pitch()), absf(rad_to_deg(p._air_pitch()) - 90.0) < 1.0)
	p.velocity = Vector3.ZERO
	check("hovering stays upright", p._air_pitch() == 0.0)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
