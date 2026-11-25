extends SceneTree
## Step 3 checks: web anchors on geometry only, high and forward; fixed-length rope; real swing;
## release cases A/B; falling strand; F3 pendulum readout.
## Run: godot --headless -s tests/step3_check.gd

const MASS := 70.0
const G := 9.8
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var p: CharacterBody3D = main.get_node("Player")
	for i in 120:
		await physics_frame
	var wl = p.get_node("WebLeft")
	var wr = p.get_node("WebRight")
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")

	# 1. No building: a straight-up shot must refuse, never hook empty air
	cam.rotation.x = -1.45
	cam.rotation.y = 0.0
	check("shot at open sky does not attach", not wl.fire(cam, p.get_rid()))
	check("sky shot leaves web idle", wl.phase == wl.Phase.IDLE)

	# 2. Left web: building face, high and forward of the player
	cam.rotation.x = -0.4
	cam.rotation.y = 0.0
	var start := p.global_position
	var fwd := Vector3(0, 0, -1)
	var ok_l: bool = wl.fire(cam, p.get_rid())
	check("left web attaches to a building face", ok_l and wl.phase == wl.Phase.SHOOT)
	var off: Vector3 = wl.anchor - start
	check("anchor is above the player (rise %.2f m)" % off.y, off.y >= wl.MIN_ANCHOR_RISE)
	check("anchor is forward of the player (%.2f m)" % off.dot(fwd), off.dot(fwd) > 1.0)
	check("anchor is left of the player (%.2f m)" % off.dot(Vector3(1, 0, 0)), off.dot(Vector3(1, 0, 0)) < 0.0)
	check("anchor height %.2f m is well up a wall" % wl.anchor.y, wl.anchor.y > 6.0)

	# 3. Swing: rope stays fixed, body leaves the floor and arcs
	var dmin := 1e9
	var dmax := 0.0
	var top := -1e9
	var vmax := 0.0
	var air := 0
	for i in 360:
		await physics_frame
		top = maxf(top, p.global_position.y)
		vmax = maxf(vmax, p.velocity.length())
		if not p.grounded:
			air += 1
		if wl.phase == wl.Phase.ROPE and i > 90:
			var d: float = p.global_position.distance_to(wl.anchor)
			dmin = minf(dmin, d)
			dmax = maxf(dmax, d)
	print("swing: rope band %.2f..%.2f (len %.2f), peak h %.2f, peak v %.2f, air %d" % [dmin, dmax, wl.length, top, vmax, air])
	check("rope never stretches past its length", dmax <= wl.length + 0.05)
	check("rope length holds (slack under 1.5 m)", wl.length - dmin < 1.5)
	check("body leaves the floor (airborne %d frames)" % air, air > 60)
	check("swing gains height (peak %.2f m)" % top, top > 3.0)
	check("swing reaches real speed (%.2f m/s)" % vmax, vmax > 8.0)
	check("tension reported while taut (%.0f N)" % wl.last_tension, wl.last_tension > 0.0)

	# 4. Release: momentum kept, strand falls, case recorded
	var v_before: Vector3 = p.velocity
	var kick: Vector3 = wl.release(fwd)
	check("release detaches", wl.phase == wl.Phase.IDLE)
	check("release returns a kick (%.1f m/s)" % kick.length(), kick.length() > 0.0)
	check("release records case %s" % wl.last_case, wl.last_case == "A" or wl.last_case == "B")
	check("strand starts falling", wl.strand_t > 0.0)
	var y0: float = wl.strand_tip.y
	for i in 30:
		await physics_frame
	check("strand falls under gravity (%.2f m)" % (y0 - wl.strand_tip.y), wl.strand_tip.y < y0)

	# 5. Kick magnitudes: case A strong, case B subtle
	var ka: Vector3 = wl.kick_for(true, fwd)
	var kb: Vector3 = wl.kick_for(false, fwd)
	check("case A kick is stronger than case B (%.1f vs %.1f m/s)" % [ka.length(), kb.length()], ka.length() > kb.length() * 2.0)
	check("case A pushes forward and up", ka.z < 0.0 and ka.y > 0.0)
	check("case B lifts gently", kb.y > 0.0 and kb.length() < 4.0)

	# 6. Right web: mirror side
	for i in 90:
		await physics_frame
	cam.rotation.x = -0.4
	var ok_r: bool = wr.fire(cam, p.get_rid())
	var offr: Vector3 = wr.anchor - p.global_position
	check("right web attaches", ok_r)
	check("right anchor is right of the player (%.2f m)" % offr.dot(Vector3(1, 0, 0)), offr.dot(Vector3(1, 0, 0)) > 0.0)

	# 7. F3 HUD shows the pendulum readout while a web is held
	var hud: Node3D = p.get_node("PhysicsHUD")
	hud._set_on(true)
	for i in 20:
		await physics_frame
	var txt: String = hud._text.text
	check("HUD shows tension and circular metrics", txt.contains("T =") and txt.contains("a_c = v^2/r") and txt.contains("F_c = m v^2/r"))
	print("HUD pendulum lines:\n", txt)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
