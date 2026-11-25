extends SceneTree
## Step 4 checks: zip course, surface-only targeting, ZIP state, pull, and the three arrivals.
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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var p: CharacterBody3D = main.get_node("Player")
	for i in 60:
		await physics_frame
	var z = p.get_node("Zip")
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")

	# 1. The zip course exists: tiered roof, two towers with a gap, a tall wall, an overhang
	var boxes: Array = main.get_node("Greybox").get_children()
	check("zip course built (>= 16 static bodies)", boxes.size() >= 16)

	# 2. Empty sky never attaches
	p.global_position = Vector3(30, 0.1, 0)
	for i in 5:
		await physics_frame
	look(cam, cam.global_position + Vector3(0, 40, 0))
	check("aim at open sky finds no target", not z.aim(cam, p.get_rid()))
	check("zip start refused without a surface", not z.start(cam, p.get_rid(), p.global_position, p.velocity))
	check("zip stays idle after a refused shot", z.phase == z.Phase.IDLE)

	# 3. Wall zip: aim at the tall tier, pull, ZIP state, push off
	look(cam, Vector3(40, 14, 0))
	check("aim finds the building face", z.aim(cam, p.get_rid()))
	check("reticle shows on a valid target", z.aim_visible())
	check("target sits on real geometry (normal %s)" % z.target_normal.snapped(Vector3.ONE * 0.01), z.target_normal.length() > 0.9)
	check("zip starts", z.start(cam, p.get_rid(), p.global_position, p.velocity))
	var saw_zip := false
	var frames := 0
	for i in 240:
		await physics_frame
		frames += 1
		if p.state == p.State.ZIP:
			saw_zip = true
		if z.phase == z.Phase.IDLE:
			break
	check("player enters ZIP state while pulling", saw_zip)
	check("pull completes (%d frames)" % frames, frames < 200)
	check("wall arrival pushes off instead of sticking (arrival %s)" % z.last_arrival, z.last_arrival == "wall" and p.velocity.length() > 1.0)
	check("zip work equals dK + dU (%.0f vs %.0f J)" % [z.work, z.last_dk + z.last_du], absf(z.work - (z.last_dk + z.last_du)) < 1.0)
	check("impulse recorded (%.0f N s)" % z.impulse.length(), z.impulse.length() > 0.0)
	check("zip displacement recorded (%.2f m)" % z.last_displacement.length(), z.last_displacement.length() > 5.0)
	check("released strand falls", z.strand_t > 0.0)

	# 4. Ledge zip: land on a tower top
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(52, 12, 20))
	var top_ok: bool = z.aim(cam, p.get_rid())
	var top_ny: float = z.target_normal.y
	check("aim finds a tower top (normal.y %.2f)" % top_ny, top_ok and top_ny > 0.6)
	z.start(cam, p.get_rid(), p.global_position, p.velocity)
	for i in 240:
		await physics_frame
		if z.phase == z.Phase.IDLE:
			break
	check("ledge arrival reported", z.last_arrival == "ledge")
	for i in 120:
		await physics_frame
	check("ledge arrival lands on the roof (y=%.2f)" % p.global_position.y, p.is_on_floor() and absf(p.global_position.y - 12.0) < 0.4)

	# 5. Vault: Space near arrival launches up and forward
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(52, 12, 20))
	z.start(cam, p.get_rid(), p.global_position, p.velocity)
	Input.action_press("jump")
	for i in 240:
		await physics_frame
		if z.phase == z.Phase.IDLE:
			break
	Input.action_release("jump")
	check("vault arrival reported", z.last_arrival == "vault")
	check("vault launches upward (vy=%.2f)" % p.velocity.y, p.velocity.y > 4.0)

	# 6. F3 shows the zip force and work-energy readouts
	var hud: Node3D = p.get_node("PhysicsHUD")
	hud._set_on(true)
	p.global_position = Vector3(59, 20, 20)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	look(cam, Vector3(52, 12, 20))
	z.start(cam, p.get_rid(), p.global_position, p.velocity)
	for i in 12:
		await physics_frame
	var txt: String = hud._text.text
	check("HUD shows F_zip vector", txt.contains("F_zip"))
	check("HUD shows zip work-energy block", txt.contains("W = F.dr") and txt.contains("dK") and txt.contains("Impulse"))
	print("HUD zip lines:\n", txt)

	# 7. The zip binding drives the controller, and it drops any active web first
	hud._set_on(false)
	z.cancel()  # end the HUD-section pull, or the next press is ignored while one is active
	for i in 3:
		await physics_frame
	p.global_position = Vector3(30, 0.1, 0)
	p.velocity = Vector3.ZERO
	for i in 5:
		await physics_frame
	var wl = p.get_node("WebLeft")
	look(cam, Vector3(40, 14, 0))
	wl.fire(cam, p.get_rid())
	check("web attached before the zip", wl.phase != wl.Phase.IDLE)
	look(cam, Vector3(40, 14, 0))
	Input.action_press("zip")
	for i in 3:
		await physics_frame
	Input.action_release("zip")
	check("zip action starts a zip through the controller", z.phase != z.Phase.IDLE)
	check("zip releases the active web", wl.phase == wl.Phase.IDLE)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
