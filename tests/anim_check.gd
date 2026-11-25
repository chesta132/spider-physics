extends SceneTree
## Step 7 checks: the grounded animation set. Run: godot --headless -s tests/anim_check.gd
## Proves the clips exist, are actually driven by state, respond to speed, and move bones —
## and that the cosmetic rig still never writes the heading (physics/movement owns that).

const PC := preload("res://scripts/player_controller.gd")
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


## Largest rotation of one bone seen over `frames` idle-process frames.
func leg_peak(sk: Skeleton3D, frames: int) -> float:
	var bone := sk.find_bone("Thigh.L")
	var peak := 0.0
	for i in frames:
		await process_frame
		peak = maxf(peak, rad_to_deg(sk.get_bone_pose_rotation(bone).get_angle()))
	return peak


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)  # greybox: these checks pin flat ground
	root.add_child(main)
	for i in 120:
		await physics_frame
	var p: CharacterBody3D = main.get_node("Player")
	var ap: AnimationPlayer = p.get_node_or_null("Visual/Model/Rig/AnimationPlayer")
	var sk: Skeleton3D = p.get_node_or_null("Visual/Model/Rig/Skeleton")
	check("AnimationPlayer under Player/Visual/Model/Rig", ap != null)
	check("Skeleton under the same rig", sk != null)
	if sk != null:
		for b in ["Shoulder.L", "UpperArm.L", "Forearm.L", "Hand.L", "Thigh.L", "LowerLeg.L",
			"Shoulder.R", "UpperArm.R", "Forearm.R", "Hand.R", "Thigh.R", "LowerLeg.R"]:
			check("expanded bone %s" % b, sk.find_bone(b) >= 0)
		check("upper arm starts at shoulder pivot (%.3f m)" % sk.get_bone_global_rest(sk.find_bone("UpperArm.L")).origin.distance_to(sk.get_bone_global_rest(sk.find_bone("Shoulder.L")).origin),
			sk.get_bone_global_rest(sk.find_bone("UpperArm.L")).origin.distance_to(sk.get_bone_global_rest(sk.find_bone("Shoulder.L")).origin) < 0.001)
	if ap == null or sk == null:
		print("RESULT: cannot continue without the rig")
		quit(1)
		return

	check("library 'moves' present (%s)" % [ap.get_animation_library_list()], ap.has_animation_library("moves"))
	for clip in ["idle", "walk", "run"]:
		check("clip moves/%s exists" % clip, ap.has_animation("moves/" + clip))
		if ap.has_animation("moves/" + clip):
			var an := ap.get_animation("moves/" + clip)
			var t := an.track_get_key_count(0) - 1
			var closed: bool = an.track_get_key_value(0, 0) == an.track_get_key_value(0, t)
			for ti in an.get_track_count():
				closed = closed and an.track_get_key_value(ti, 0) == an.track_get_key_value(ti, an.track_get_key_count(ti) - 1)
			check("moves/%s loops (mode %d, first key == last key: %s)" % [clip, an.loop_mode, closed],
				an.loop_mode == Animation.LOOP_LINEAR and closed)

	# Rest: IDLE and the idle clip running.
	check("rest state IDLE (%s)" % p.STATE_NAMES[p.state], p.state == PC.State.IDLE)
	check("rest clip is moves/idle (%s)" % ap.current_animation, ap.current_animation == "moves/idle")
	check("crossfade 0.15-0.2 s (%.2f)" % PC.ANIM_FADE, PC.ANIM_FADE >= 0.15 and PC.ANIM_FADE <= 0.2)

	# Idle must be subtle: legs at rest, torso barely moves, head bobs about a centimetre.
	var idle_leg := await leg_peak(sk, 40)
	var torso := sk.find_bone("Torso")
	var torso_peak := 0.0
	var head_lo := 1e9
	var head_hi := -1e9
	var head := sk.find_bone("Head")
	for i in 40:
		await process_frame
		torso_peak = maxf(torso_peak, rad_to_deg(sk.get_bone_pose_rotation(torso).get_angle()))
		var hy: float = sk.get_bone_pose_position(head).y
		head_lo = minf(head_lo, hy)
		head_hi = maxf(head_hi, hy)
	check("idle leaves the legs at rest (peak %.2f deg)" % idle_leg, idle_leg < 0.01)
	check("idle torso sway 1-2 deg (peak %.2f)" % torso_peak, torso_peak > 0.5 and torso_peak < 3.0)
	# Head bob from the clip's own keys: a 40-frame sample covers only part of a 2 s loop.
	var bob := 0.0
	var an_idle := ap.get_animation("moves/idle")
	for ti in an_idle.get_track_count():
		if str(an_idle.track_get_path(ti)) != "Skeleton:Head" or an_idle.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var lo := 1e9
		var hi := -1e9
		for k in an_idle.track_get_key_count(ti):
			var v: Vector3 = an_idle.track_get_key_value(ti, k)
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		bob = maxf(bob, hi - lo)
	check("idle head bob ~1 cm (%.1f mm peak-to-peak)" % (bob * 1000.0), bob > 0.008 and bob < 0.012)
	check("idle head actually moves while playing (%.2f mm sampled)" % ((head_hi - head_lo) * 1000.0), head_hi > head_lo)

	# Camera orbit must not turn the mesh, even with the clips running.
	var face0: float = p.visual.rotation.y
	var pivot: Node3D = p.get_node("Pivot")
	pivot.yaw = 1.2
	for i in 30:
		await physics_frame
	check("orbit while idle leaves Visual.rotation.y alone", absf(p.visual.rotation.y - face0) < 0.001)
	pivot.yaw = 0.0
	for i in 30:
		await physics_frame

	# Walk.
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	var hv := Vector3(p.velocity.x, 0, p.velocity.z).length()
	var walk_ss: float = ap.speed_scale
	var walk_leg := await leg_peak(sk, 30)
	check("1 s of move_forward -> WALK (%s, %.2f m/s)" % [p.STATE_NAMES[p.state], hv],
		p.state == PC.State.WALK and hv > 3.0)
	check("walk clip playing (%s)" % ap.current_animation, ap.current_animation == "moves/walk")
	check("walk swing is non-trivial (Leg.L peak %.1f deg)" % walk_leg, walk_leg > 15.0)
	check("walk speed_scale follows speed (%.2f at %.2f m/s)" % [walk_ss, hv], walk_ss > 0.8 and walk_ss < 1.0)

	# Run.
	Input.action_press("sprint")
	for i in 60:
		await physics_frame
	hv = Vector3(p.velocity.x, 0, p.velocity.z).length()
	var run_ss: float = ap.speed_scale
	var run_leg := await leg_peak(sk, 30)
	check("sprint -> RUN (%s, %.2f m/s)" % [p.STATE_NAMES[p.state], hv], p.state == PC.State.RUN and hv > 7.0)
	check("run clip playing (%s)" % ap.current_animation, ap.current_animation == "moves/run")
	check("run swing is bigger than walk (Leg.L peak %.1f vs %.1f deg)" % [run_leg, walk_leg], run_leg > walk_leg)
	check("speed_scale rises from walk to run (%.2f -> %.2f)" % [walk_ss, run_ss], run_ss > walk_ss)
	check("run speed_scale clamped <= 1.4 (%.2f)" % run_ss, run_ss <= 1.4 + 0.001)

	# Heading still follows travel only.
	var fwd := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check("mesh faces travel while running (dot %.3f)" % p.visual.global_transform.basis.z.dot(fwd),
		p.visual.global_transform.basis.z.dot(fwd) > 0.98)

	# A state with no clip of its own keeps the last grounded clip playing.
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 30:
		await physics_frame
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	for i in 4:
		await physics_frame
	check("jump keeps a grounded clip playing (%s, %s)" % [p.STATE_NAMES[p.state], ap.current_animation],
		p.state == PC.State.JUMP and ap.current_animation.begins_with("moves/") and ap.is_playing())

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
