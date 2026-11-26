extends SceneTree
## Step 5 checks: wall attach, crawl, run, wall jump, top-edge climb and drop, F3 wall readout.
## Run: godot --headless -s tests/step5_check.gd

const PC := preload("res://scripts/player_controller.gd")
const MASS := 70.0
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)  # these checks pin greybox geometry
	root.add_child(main)
	var p: CharacterBody3D = main.get_node("Player")
	for i in 30:
		await physics_frame
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")
	var wall = p.get_node("Wall")

	# 1. Attach: moving into the tall free-standing wall at x=39.4 (z -29..-15, 20 m tall)
	cam.rotation.y = 0.0
	cam.rotation.x = -0.3
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	check("moving into a wall attaches", wall.active())
	check("attached to the wall face (normal.x %.2f)" % wall.normal.x, wall.normal.x < -0.9)
	check("state reads WALL CRAWL on a slow attach", p.state == p.State.WALL_CRAWL)

	# 2. Crawl: W climbs the wall, and the body is held on the face
	var y0: float = p.global_position.y
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var climbed: float = p.global_position.y - y0
	check("W climbs the wall (%.2f m in 1 s)" % climbed, climbed > 2.0)
	check("crawl keeps the body on the face (x %.2f)" % p.global_position.x, p.global_position.x > 38.0)

	# 3. Wall jump: Space launches off the normal and upward
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	check("Space off the wall is a WALL JUMP (state %s)" % p.STATE_NAMES[p.state], p.state == p.State.WALL_JUMP)
	check("wall jump pushes away from the wall (vx %.1f)" % p.velocity.x, p.velocity.x < -4.0)
	check("wall jump goes up (vy %.1f)" % p.velocity.y, p.velocity.y > 4.0)
	check("wall jump releases the wall", not wall.active())
	for i in 60:
		await physics_frame
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame

	# 4. Wall run: fast lateral entry along the face keeps the run state
	p.global_position = Vector3(38.6, 8.0, -18)
	p.velocity = Vector3(0, 0, -11)
	Input.action_press("move_right")  # press into the face; D strafes along it
	var seen_run := false
	var run_speed := 0.0
	for i in 40:
		await physics_frame
		if p.state == p.State.WALL_RUN:
			seen_run = true
			run_speed = maxf(run_speed, p.wall_node.wall_vel.length())
	Input.action_release("move_right")
	check("fast entry reaches WALL RUN", seen_run)
	check("run holds its entry speed (%.1f m/s)" % run_speed, run_speed > 6.0)
	check("run has gentle gravity (vy %.2f after 0.67 s)" % p.wall_node.wall_vel.y, p.wall_node.wall_vel.y > -3.5)
	for i in 30:
		await physics_frame
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame

	# 5. Top edge: climb the whole wall and land on the roof, never Watching
	p.global_position = Vector3(38.6, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 15:
		await physics_frame
	Input.action_release("move_right")
	Input.action_press("move_forward")
	var saw_edge_up := false
	var saw_watch := false
	for i in 400:
		await physics_frame
		if p.state == p.State.WALL_EDGE_UP:
			saw_edge_up = true
		if p.state == p.State.WATCHING:
			saw_watch = true
		if not wall.active() and p.grounded:
			break
	Input.action_release("move_forward")
	check("top edge reports WALL EDGE UP", saw_edge_up)
	check("top edge never enters Watching", not saw_watch)
	check("top edge lands on the roof (y=%.2f)" % p.global_position.y, p.grounded and p.global_position.y > 19.5)
	for i in 30:
		await physics_frame
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame

	# 6. Bottom edge: walking down the face to the floor hands off to a step-down state
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	Input.action_press("move_back")
	var saw_edge_down := false
	for i in 240:
		await physics_frame
		if p.state == p.State.WALL_EDGE_DOWN:
			saw_edge_down = true
		if not wall.active() and p.grounded:
			break
	Input.action_release("move_back")
	check("walking down the face hands off to WALL EDGE DOWN", saw_edge_down)
	check("bottom edge lands on the floor", p.grounded and p.global_position.y < 0.5)
	for i in 30:
		await physics_frame
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame

	# 7. F3: wall normal force N and grip force f on the FBD, and the wall line in the readout
	var hud: Node3D = p.get_node("PhysicsHUD")
	hud._set_on(true)
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	for i in 5:
		await physics_frame
	var txt: String = hud._text.text
	check("F3 shows the wall line (N and f)", txt.contains("Wall: N =") and txt.contains("f ="))
	check("wall normal force is on the FBD (%.0f N)" % p.f_wall.length(), p.f_wall.length() > 0.0)
	check("grip force balances weight (%.0f N)" % p.f_grip.length(), absf(p.f_grip.length() - MASS * 9.8) < 1.0)
	check("ordinary F_N is zero on a wall", p.f_n == Vector3.ZERO)
	hud._set_on(false)

	# 8. A/D read as screen left/right on the face (camera aimed at the wall, yaw 90)
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	cam.rotation.y = deg_to_rad(-90.0)  # camera forward is -Z, so -90 looks +X at the face
	cam.rotation.x = -0.2
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_forward")  # W is into the face when the camera looks at it
	for i in 25:
		await physics_frame
	Input.action_release("move_forward")
	check("attaches while the camera looks at the face", wall.active())
	var z0: float = p.global_position.z
	Input.action_press("move_right")
	for i in 20:
		await physics_frame
	Input.action_release("move_right")
	check("D strafes screen-right on the face (dz %.2f)" % (p.global_position.z - z0), p.global_position.z > z0 + 0.3)
	check("strafe axis matches the camera right (dot %.2f)" % p.wall_node.right.dot(cam.global_transform.basis.x),
		p.wall_node.right.dot(cam.global_transform.basis.x) > 0.9)

	# 9. Grip: with no input the body stops dead on the face instead of sliding
	for i in 10:
		await physics_frame  # let the grip bring the strafe to a stop
	var z_hold: float = p.global_position.z
	for i in 40:
		await physics_frame
	check("no input holds still on the wall (drift %.3f m)" % absf(p.global_position.z - z_hold), absf(p.global_position.z - z_hold) < 0.02)
	check("still attached after holding (no float-off)", wall.active())

	# 10. Sprint + W is an explicit WALL RUN, faster than the crawl
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	cam.rotation.y = 0.0
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	var y_run0: float = p.global_position.y
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var saw_sprint_run := false
	for i in 30:
		await physics_frame
		if p.state == p.State.WALL_RUN:
			saw_sprint_run = true
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var run_climb: float = p.global_position.y - y_run0
	check("Shift + W enters WALL RUN", saw_sprint_run)
	check("wall run climbs faster than the crawl (%.2f m in 0.5 s)" % run_climb, run_climb > 2.0)

	# 11. Outer corner: strafing past the edge wraps onto the perpendicular face
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	cam.rotation.y = deg_to_rad(-90.0)
	p.global_position = Vector3(38.5, 5.0, -16)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	Input.action_release("move_forward")
	check("attached before the corner", wall.active())
	Input.action_press("move_right")
	var wrapped := false
	var prev_fwd: Vector3 = p.visual.global_transform.basis.z
	var max_yaw_step := 0.0
	for i in 140:
		await physics_frame
		var fwd: Vector3 = p.visual.global_transform.basis.z
		max_yaw_step = maxf(max_yaw_step, prev_fwd.angle_to(fwd))
		prev_fwd = fwd
		if wall.normal.z > 0.9:
			wrapped = true
			break
	Input.action_release("move_right")
	for i in 25:  # let the visual finish turning onto the new face
		await physics_frame
		var fwd: Vector3 = p.visual.global_transform.basis.z
		max_yaw_step = maxf(max_yaw_step, prev_fwd.angle_to(fwd))
		prev_fwd = fwd
	check("corner wrap turns smoothly (max body step %.2f rad)" % max_yaw_step, max_yaw_step < 0.6)
	check("corner wrap adopts the perpendicular face (normal %s)" % wall.normal, wrapped)
	check("corner wrap keeps the body on a wall", wall.active())
	check("corner wrap stays in a wall state (state %s)" % p.STATE_NAMES[p.state], p.state == p.State.WALL_CRAWL or p.state == p.State.WALL_RUN)

	# 12. Climb-over is interpolated, not a teleport
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	cam.rotation.y = 0.0
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	Input.action_press("move_forward")
	var climb_frames := 0
	var max_step := 0.0
	var prev: Vector3 = p.global_position
	for i in 400:
		await physics_frame
		if p.climbing:
			climb_frames += 1
			max_step = maxf(max_step, p.global_position.distance_to(prev))
		prev = p.global_position
		if not p.climbing and p.grounded and not wall.active():
			break
	Input.action_release("move_forward")
	check("climb-over spans several frames (%d)" % climb_frames, climb_frames >= 8)
	check("climb-over never teleports (max step %.2f m)" % max_step, max_step < 0.6)
	check("climb-over ends grounded on the roof (y=%.2f)" % p.global_position.y, p.grounded and p.global_position.y > 19.5)

	# 13. The dummy clings chest-first to the wall while crawling: body +Z is the inward normal and
	# its up runs along the face, instead of standing upright and facing the wall.
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	cam.rotation.y = deg_to_rad(-90.0)
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	var face: Basis = p.visual.global_transform.basis
	check("dummy puts its chest on the wall (basis.z . -n = %.2f)" % face.z.dot(-wall.normal), face.z.dot(-wall.normal) > 0.9)
	check("dummy's up runs along the face (basis.y . up = %.2f)" % face.y.dot(Vector3.UP), face.y.dot(Vector3.UP) > 0.9)

	# 14. Wall jump while still holding into the wall must not re-grab the same face
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	var reattached := false
	for i in 5:
		await physics_frame
		if wall.active():
			reattached = true
	check("wall jump with W held does not re-attach the same wall", not reattached)
	check("wall jump with W held still launches away (vx %.1f)" % p.velocity.x, p.velocity.x < -3.0)
	Input.action_release("move_forward")
	for i in 60:
		await physics_frame
	# after the grace window the same face grabs again
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	Input.action_release("move_forward")
	check("the same face grabs again after the cooldown", wall.active())

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
