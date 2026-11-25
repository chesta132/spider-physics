extends SceneTree
## Step 4 checks: Ctrl zip, outer-corner perch hints, Watching state, no-hint forward boost,
## and the F3 zip metrics for both modes.
## Run: godot --headless -s tests/step4_check.gd

const MASS := 70.0
const G := 9.8
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func look(cam: Camera3D, at: Vector3) -> void:
	var dir := (at - cam.global_position).normalized()
	cam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), cam.global_position)


func _initialize() -> void:
	# 1. Binding: zip is Ctrl only, webs keep the mouse buttons
	var cfg: Dictionary = ProjectSettings.get_setting("input/zip", {})
	var zip_ev: Array = cfg.get("events", [])
	var ctrl := false
	var mouse := false
	for e in zip_ev:
		if e is InputEventKey and e.keycode == KEY_CTRL:
			ctrl = true
		if e is InputEventMouseButton:
			mouse = true
	check("zip bound to Ctrl", ctrl)
	check("zip not bound to a mouse button", not mouse)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var p: CharacterBody3D = main.get_node("Player")
	for i in 60:
		await physics_frame
	var z = p.get_node("Zip")
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")

	# 2. Perch hint on an outer corner, none at empty sky
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(49.8, 12, 17.8))
	var has: bool = z.find_perch(cam, p.get_rid())
	var perch_pt: Vector3 = z.perch
	check("perch hint found on a tower corner", has)
	check("hint sits on the roof top (y=%.2f)" % perch_pt.y, absf(perch_pt.y - 12.0) < 0.3)
	look(cam, cam.global_position + Vector3(0, 40, 0))
	check("no perch hint at open sky", not z.find_perch(cam, p.get_rid()))

	# 3. Ctrl with a hint: zip to the perch, settle into WATCHING
	look(cam, Vector3(49.8, 12, 17.8))
	Input.action_press("zip")
	await physics_frame
	Input.action_release("zip")
	var saw_zip := false
	var reached := false
	for i in 240:
		await physics_frame
		if p.state == p.State.ZIP:
			saw_zip = true
		if p.state == p.State.WATCHING:
			reached = true
			break
	check("zip entered the ZIP state", saw_zip)
	check("zip settles into WATCHING", reached)
	check("watching on the perch point (y=%.2f)" % p.global_position.y, absf(p.global_position.y - 12.0) < 0.4)
	var hold: Vector3 = p.global_position
	for i in 90:
		await physics_frame
	check("watching holds still for 1.5 s (moved %.3f m)" % p.global_position.distance_to(hold), p.global_position.distance_to(hold) < 0.05)
	check("still WATCHING while idle", p.state == p.State.WATCHING)

	# 4. Space from the perch: point launch
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	check("Space launches off the perch (vy=%.2f)" % p.velocity.y, p.velocity.y > 4.0)
	check("watching ends on launch", p.state != p.State.WATCHING)

	# 5. WASD from the perch also ends watching
	for i in 60:
		await physics_frame
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(49.8, 12, 17.8))
	z.start_perch(cam, p.get_rid(), p.global_position, p.velocity)
	for i in 240:
		await physics_frame
		if p.state == p.State.WATCHING:
			break
	check("perched again for the WASD test", p.state == p.State.WATCHING)
	Input.action_press("move_forward")
	for i in 10:
		await physics_frame
	Input.action_release("move_forward")
	check("WASD ends watching", p.state != p.State.WATCHING)

	# 6. No hint: forward web-zip boost, then detach
	for i in 30:
		await physics_frame
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, cam.global_position + Vector3(0, 40, 0))
	var started: bool = z.start_boost(Vector3(0, 0, -1), p.global_position, p.velocity)
	check("boost starts with no perch", started and z.mode == "boost")
	var boosted := false
	var peak_speed := 0.0
	for i in 60:
		await physics_frame
		peak_speed = maxf(peak_speed, p.velocity.length())
		if z.last_arrival == "boost":
			boosted = true
			break
	check("boost yanks the body forward (peak %.1f m/s)" % peak_speed, peak_speed > 15.0)
	check("boost detaches and drops a strand", boosted and z.strand_t > 0.0)
	check("boost leaves forward momentum (vz=%.1f)" % p.velocity.z, p.velocity.z < -12.0)

	# 7. F3 metrics during a perch zip
	var hud: Node3D = p.get_node("PhysicsHUD")
	hud._set_on(true)
	for i in 30:
		await physics_frame
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(49.8, 12, 17.8))
	z.start_perch(cam, p.get_rid(), p.global_position, p.velocity)
	var mid_txt := ""
	for i in 8:
		await physics_frame
		mid_txt = hud._text.text
	check("HUD shows F_zip during the perch zip", mid_txt.contains("F_zip") and mid_txt.contains("ZIP [perch]"))
	check("HUD shows work, dK, dU and impulse", mid_txt.contains("W = F.dr") and mid_txt.contains("dK") and mid_txt.contains("Impulse"))
	for i in 240:
		await physics_frame
		if z.phase == z.Phase.IDLE:
			break
	check("zip work equals dK + dU (%.0f vs %.0f J)" % [z.work, z.last_dk + z.last_du], absf(z.work - (z.last_dk + z.last_du)) < 1.0)
	print("HUD zip lines:\n", mid_txt)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
