extends SceneTree
## Air-state animation and landing-impact check. Physics is driven by the existing controller.
var fails := 0

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)
	root.add_child(main)
	for i in 120:
		await physics_frame
	var p: CharacterBody3D = main.get_node("Player")
	var ap: AnimationPlayer = p.get_node("Visual/Model/Rig/AnimationPlayer")
	check("initial idle clip", ap.current_animation == "moves/idle")

	# Use the controller's own launch method, but start from a raised test position so the
	# existing LAND_DROP threshold is exercised without changing movement code.
	p.global_position += Vector3.UP * 4.0
	p.grounded = true
	p._launch()
	var saw_jump := false
	var saw_fall := false
	var saw_land := false
	var fall_scale := 0.0
	for i in 300:
		await physics_frame
		if p.state == p.State.JUMP and ap.current_animation == "moves/jump":
			saw_jump = true
		if p.state == p.State.FALL and ap.current_animation == "moves/fall":
			saw_fall = true
			fall_scale = ap.speed_scale
		if p.state == p.State.LAND and ap.current_animation == "moves/land":
			saw_land = true
			break
	check("launch enters JUMP", saw_jump)
	check("descent enters FALL clip", saw_fall)
	check("fall speed_scale responds (%.2f)" % fall_scale, fall_scale >= 0.8 and fall_scale <= 1.4)
	check("heavy touchdown enters LAND clip", saw_land)
	var crack := root.find_child("LandingCrack", true, false)
	check("landing crack spawned on surface", crack != null)
	if crack:
		check("crack is above ground", crack.global_position.y >= -0.001)
	# Existing landing behavior ends when input is supplied; crack follows that lifecycle.
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	Input.action_release("move_forward")
	check("ground clip resumes after landing", ap.current_animation == "moves/walk" or ap.current_animation == "moves/idle")
	check("landing crack persists briefly to fade", root.find_child("LandingCrack", true, false) != null)
	for i in 100:
		await physics_frame
	check("landing crack cleaned after fade timeout", root.find_child("LandingCrack", true, false) == null)
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
