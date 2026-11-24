extends SceneTree
## Step 1 checks. Run: godot --headless -s tests/step1_check.gd

const PC := preload("res://scripts/player_controller.gd")
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	# Pure force model (Giancoli Ch. 4-6)
	var v := Vector3.ZERO
	for i in 60 * 30:  # 30 s at 60 Hz, gravity + drag only
		v += (Vector3(0, -PC.MASS * PC.G, 0) + PC.drag(v)) / PC.MASS / 60.0
	var vt := sqrt(PC.MASS * PC.G / PC.DRAG_K)
	check("terminal velocity within 2%% of sqrt(mg/k)=%.2f (got %.2f)" % [vt, -v.y], absf(-v.y - vt) / vt < 0.02)
	const DT := 1.0 / 60.0
	check("traction capped at mu*m*g", absf(PC.traction(Vector3.ZERO, Vector3(9, 0, 0), DT).length() - PC.MU_GRIP * PC.MASS * PC.G) < 0.01)
	check("traction uncapped for small dv", absf(PC.traction(Vector3.ZERO, Vector3(0.1, 0, 0), DT).x - 0.1 * PC.MASS / DT) < 0.01)
	# Crisp stop: from run speed, release keys, measure time to rest (no drag, ground only)
	var run_v := Vector3(PC.RUN_SPEED, 0, 0)
	var run_f := 0
	while run_v.length() > 0.02 and run_f < 600:
		run_v += PC.traction(run_v, Vector3.ZERO, DT) / PC.MASS * DT
		run_f += 1
	print("stop time from run speed: %.3f s" % (run_f * DT))
	check("run stop within 0.17 s (got %.3f s)" % (run_f * DT), run_f * DT < 0.17)
	var walk_v := Vector3(PC.WALK_SPEED, 0, 0)
	var walk_f := 0
	while walk_v.length() > 0.02 and walk_f < 600:
		walk_v += PC.traction(walk_v, Vector3.ZERO, DT) / PC.MASS * DT
		walk_f += 1
	check("walk stop within 0.1 s (got %.3f s)" % (walk_f * DT), walk_f * DT < 0.1)
	check("drag opposes motion: F_d=-k v^2", absf(PC.drag(Vector3(0, -10, 0)).y - 30.0) < 1e-6)
	check("jump speed sqrt(2gh)=4.85", absf(PC.jump_speed() - 4.8497) < 0.001)
	check("jump reaches 1.2 m (v^2/2g)", absf(PC.jump_speed() * PC.jump_speed() / (2 * PC.G) - PC.JUMP_HEIGHT) < 1e-6)
	check("state: idle", PC.state_for(false, true, 0, false, false) == PC.State.IDLE)
	check("state: walk", PC.state_for(false, true, 0, true, false) == PC.State.WALK)
	check("state: run", PC.state_for(false, true, 0, true, true) == PC.State.RUN)
	check("state: jump (rising)", PC.state_for(false, false, 3, false, false) == PC.State.JUMP)
	check("state: fall (falling)", PC.state_for(false, false, -2, false, false) == PC.State.FALL)
	check("state: fly overrides", PC.state_for(true, false, -2, true, true) == PC.State.FLY)

	# Integration: drop onto greybox ground, must land and rest with N + mg = 0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 120:
		await physics_frame
	var p: CharacterBody3D = main.get_node("Player")
	check("player lands on ground (y=%.3f)" % p.global_position.y, p.is_on_floor() and absf(p.global_position.y) < 0.05)
	check("resting FBD balance |F_g+F_N| < 0.01 N", (p.f_g + p.f_n).length() < 0.01)
	check("resting state IDLE", p.state == PC.State.IDLE)
	check("physics interpolation enabled (stutter fix)", ProjectSettings.get_setting("physics/common/physics_interpolation") == true)
	# Camera follows player and orbiting while idle must not turn the mesh
	var rig: Node3D = p.get_node("Pivot")
	check("camera rig follows player (dist %.2f m)" % rig.global_position.distance_to(p.global_position), rig.global_position.distance_to(p.global_position) < 2.0)
	var face0: float = p.visual.rotation.y
	rig.yaw += 1.0
	for i in 30:
		await physics_frame
	check("orbit while idle does not rotate player", absf(p.visual.rotation.y - face0) < 0.001)
	rig.yaw = 0.0  # movement checks below assume camera looks down -Z
	for i in 30:
		await physics_frame
	# Camera collision: sweep pitch and yaw, camera must stay above ground and outside blocks
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")
	var below := 0
	var inside := 0
	for pitch_s in [-0.6, 0.0, 0.5, 1.0, 1.5]:
		for yaw_s in 8:
			rig.pitch = pitch_s
			rig.yaw = yaw_s * TAU / 8.0
			for i in 20:
				await physics_frame
			var c := cam.global_position
			if c.y < 0.05:
				below += 1
			for box in main.get_node("Greybox").get_children():
				var mesh: BoxMesh = box.get_child(1).mesh
				if mesh.size.x > 100.0:
					continue  # ground plane
				var local: Vector3 = c - (box as Node3D).global_position
				var half := mesh.size / 2.0 + Vector3.ONE * 0.2
				if absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z:
					inside += 1
	check("camera never below ground in pitch/yaw sweep (%d hits)" % below, below == 0)
	check("camera never inside a block in pitch/yaw sweep (%d hits)" % inside, inside == 0)
	rig.pitch = 1.5
	rig.yaw = 0.0
	for i in 20:
		await physics_frame
	check("pitch 1.5 rad puts camera high above player (y=%.2f)" % cam.global_position.y, cam.global_position.y > p.global_position.y + 4.0)
	rig.pitch = 0.35
	rig.yaw = 0.0
	for i in 20:
		await physics_frame

	var hud: Node3D = p.get_node("PhysicsHUD")
	check("F3 HUD off at startup", not hud._on)
	hud._set_on(true)
	for i in 5:
		await process_frame
	var txt: String = hud._text.text
	check("HUD shows physics readout when on", txt.begins_with("PHYSICS") and txt.contains("Momentum") and txt.contains("F_g"))
	check("HUD dev block present in debug build", txt.contains("DEV") == OS.is_debug_build())
	print("HUD sample:\n", txt)

	# Input path: walk, run, jump (camera yaw 0, so W = -Z)
	Input.action_press("move_forward")
	for i in 90:
		await physics_frame
	var hv := Vector3(p.velocity.x, 0, p.velocity.z).length()
	check("walk reaches ~5 m/s (got %.2f)" % hv, p.state == PC.State.WALK and absf(hv - PC.WALK_SPEED) < 0.3)
	var fwd := Vector3(p.velocity.x, 0, p.velocity.z).normalized()
	check("mesh faces travel direction (dot %.3f)" % p.visual.global_transform.basis.z.dot(fwd), p.visual.global_transform.basis.z.dot(fwd) > 0.98)
	Input.action_press("sprint")
	for i in 90:
		await physics_frame
	hv = Vector3(p.velocity.x, 0, p.velocity.z).length()
	check("run reaches ~9 m/s (got %.2f)" % hv, p.state == PC.State.RUN and absf(hv - PC.RUN_SPEED) < 0.3)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 60:
		await physics_frame
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	check("jump enters JUMP state, v_y ~ sqrt(2gh), impulse = m*v_y", p.state == PC.State.JUMP and absf(p.last_impulse.y - PC.MASS * PC.jump_speed()) < 1.0)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
