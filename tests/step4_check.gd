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
	check("hint point cleared when the camera leaves the building", z.perch == Vector3.ZERO and not z.has_perch)
	await process_frame
	await process_frame
	check("hint icon hidden once the camera leaves the building", not z._reticle.visible)
	# Off-axis: the same corner, 30 degrees away from the crosshair, must not hint
	look(cam, Vector3(49.8, 12, 17.8))
	var on_axis: bool = z.find_perch(cam, p.get_rid())
	var corner: Vector3 = z.perch
	var to_corner := (corner - cam.global_position).normalized()
	var off := to_corner.rotated(Vector3.UP, deg_to_rad(30.0))
	look(cam, cam.global_position + off * 20.0)
	check("hint needs the corner near the crosshair (on-axis=%s)" % on_axis, on_axis and not z.find_perch(cam, p.get_rid()))

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
	# The zip web must fall and fade like a normal web strand, not freeze on arrival
	var sy0: float = z.strand_tip.y
	for i in 30:
		await physics_frame
	check("zip strand keeps falling after arrival (%.2f m)" % (sy0 - z.strand_tip.y), z.strand_tip.y < sy0 - 0.2)
	for i in 60:
		await physics_frame
	check("zip strand fades near the end (alpha %.2f)" % z._strand_mat.albedo_color.a, z._strand_mat.albedo_color.a < 0.95)
	for i in 60:
		await physics_frame
	check("zip strand despawns after its lifetime", z.strand_t <= 0.0 and not z._strand.visible)
	var hold: Vector3 = p.global_position
	for i in 90:
		await physics_frame
	check("watching holds still for 1.5 s (moved %.3f m)" % p.global_position.distance_to(hold), p.global_position.distance_to(hold) < 0.05)
	check("still WATCHING while idle", p.state == p.State.WATCHING)
	# Ctrl while watching, aimed at nothing, must not disturb the perch
	look(cam, cam.global_position + Vector3(0, 40, 0))
	Input.action_press("zip")
	for i in 6:
		await physics_frame
	Input.action_release("zip")
	check("Ctrl with nothing aimed keeps WATCHING", p.state == p.State.WATCHING)

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

	# 6. Ctrl paths with no perch hint: empty air does nothing, a real face boosts
	for i in 30:
		await physics_frame
	p.global_position = Vector3(30, 0.1, 0)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	look(cam, cam.global_position + Vector3(0, 40, 0))
	check("no perch hint at open sky for the Ctrl test", not z.find_perch(cam, p.get_rid()))
	var wl_c = p.get_node("WebLeft")
	var v_before: Vector3 = p.velocity
	var st_before: int = p.state
	Input.action_press("zip")
	for i in 6:
		await physics_frame
	Input.action_release("zip")
	check("Ctrl at empty air does nothing (v=%.2f)" % p.velocity.length(), p.velocity.length() < 0.5)
	check("Ctrl at empty air keeps the state (%d -> %d)" % [st_before, p.state], p.state == st_before)
	check("Ctrl at empty air starts no zip and no web", z.phase == z.Phase.IDLE and wl_c.phase == wl_c.Phase.IDLE)

	# Real wall face, roof too far to be a perch: web pull, ZIP state, release, no web left attached
	p.global_position = Vector3(80, 0.1, 20)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	look(cam, Vector3(90, 10, 20))
	check("tall wall gives no perch hint (roof out of range)", not z.find_perch(cam, p.get_rid()))
	Input.action_press("zip")
	var boost_zip := false
	for i in 90:
		await physics_frame
		if p.state == p.State.ZIP:
			boost_zip = true
		if z.last_arrival == "boost":
			break
	Input.action_release("zip")
	check("Ctrl at a real face fires a web boost", z.last_arrival == "boost")
	check("boost runs in the ZIP state", boost_zip)
	check("boost hands over forward speed (%.1f m/s)" % p.velocity.length(), p.velocity.length() > 6.0)
	check("boost releases the web", z.phase == z.Phase.IDLE and wl_c.phase == wl_c.Phase.IDLE)
	check("boost drops a falling strand", z.strand_t > 0.0)
	check("boost never enters the JUMP state", p.state != p.State.JUMP)

	# 8. Perch hints from below, and the body faces outward once watching
	for i in 30:
		await physics_frame
	p.global_position = Vector3(30, 0.1, 0)
	p.velocity = Vector3.ZERO
	for i in 5:
		await physics_frame
	look(cam, Vector3(38, 11.9, 1.0))
	check("perch hint found from below, on the wall face", z.find_perch(cam, p.get_rid()))
	check("hint sits on the roof above the face (y=%.2f)" % z.perch.y, z.perch.y > 13.0)
	check("hint outward points away from the building (x=%.2f)" % z.perch_outward.x, z.perch_outward.x < -0.5)
	z.start_perch(cam, p.get_rid(), p.global_position, p.velocity)
	for i in 300:
		await physics_frame
		if p.state == p.State.WATCHING:
			break
	check("zip from below reaches WATCHING", p.state == p.State.WATCHING)
	var facing: Vector3 = p.get_node("Visual").global_transform.basis.z
	check("body faces outward over the drop (dot %.2f)" % facing.dot(z.perch_outward), facing.dot(z.perch_outward) > 0.9)
	Input.action_press("move_forward")
	for i in 3:
		await physics_frame
	Input.action_release("move_forward")
	for i in 30:
		await physics_frame

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
