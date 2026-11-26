extends SceneTree
## Wall-traversal animation check: the five wall states drive their clips, the body frame puts the
## body's "down" into the face (RUN) or its chest on the face (CRAWL), the crawl freezes and resumes,
## and every new clip exists and loops. Run: godot --headless -s tests/wall_anim_check.gd

const PC := preload("res://scripts/player_controller.gd")
const CLIPS := {"wall_crawl": 44, "wall_jump": 46, "wall_edge_up": 64, "wall_edge_down": 46}
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)  # greybox: the tall wall at x=39.4 is the test face
	root.add_child(main)
	for i in 120:
		await physics_frame
	var p: CharacterBody3D = main.get_node("Player")
	var ap: AnimationPlayer = p.get_node("Visual/Model/Rig/AnimationPlayer")
	var sk: Skeleton3D = p.get_node("Visual/Model/Rig/Skeleton")
	var wall = p.get_node("Wall")
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")

	# 1. Every wall clip is in the library, loops, and closes on its first pose.
	for clip in CLIPS:
		var ok: bool = ap.has_animation("moves/" + clip)
		check("clip moves/%s exists" % clip, ok)
		if not ok:
			continue
		var an := ap.get_animation("moves/" + clip)
		var closed := true
		var keys := 0
		for t in an.get_track_count():
			closed = closed and an.track_get_key_value(t, 0) == an.track_get_key_value(t, an.track_get_key_count(t) - 1)
			keys += an.track_get_key_count(t)
		check("moves/%s loops (mode %d) and closes on its first pose" % [clip, an.loop_mode],
			an.loop_mode == Animation.LOOP_LINEAR and closed)
		check("moves/%s keeps its minimal key set (%d keys, %d tracks)" % [clip, keys, an.get_track_count()],
			keys == CLIPS[clip] and an.get_track_count() == 16)

	# 2. Attach to the face, then crawl: chest into the wall, up the wall, moving limbs.
	#    Nothing on the face is animated while the body holds still.
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
	check("attached to the face (normal %s)" % wall.normal, wall.active() and wall.normal.x < -0.9)
	for i in 15:
		await physics_frame
	var n: Vector3 = wall.normal
	var b: Basis = p.visual.global_transform.basis
	check("crawl plays moves/wall_crawl (%s, state %s)" % [ap.current_animation, p.STATE_NAMES[p.state]],
		p.state == PC.State.WALL_CRAWL and ap.current_animation == "moves/wall_crawl")
	check("crawl puts the chest on the face (basis.z . -n = %.3f)" % b.z.dot(-n), b.z.dot(-n) > 0.95)
	check("crawl keeps the body's up along the face (basis.y . up = %.3f)" % b.y.dot(Vector3.UP), b.y.dot(Vector3.UP) > 0.95)
	check("crawl pulls the body onto the face (%.2f m toward the face)" % (p.visual.global_position - p.global_position).dot(-n),
		(p.visual.global_position - p.global_position).dot(-n) > 0.15)
	check("still crawl -> frozen clip (speed_scale %.2f)" % ap.speed_scale, ap.speed_scale == 0.0)
	var frozen := sk.get_bone_pose_rotation(sk.find_bone("UpperArm.L"))
	for i in 20:
		await physics_frame
	check("frozen crawl holds the pose", sk.get_bone_pose_rotation(sk.find_bone("UpperArm.L")).is_equal_approx(frozen))
	Input.action_press("move_forward")
	var peak := 0.0
	var prev := sk.get_bone_pose_rotation(sk.find_bone("UpperArm.L"))
	for i in 40:
		await physics_frame
		var q := sk.get_bone_pose_rotation(sk.find_bone("UpperArm.L"))
		peak = maxf(peak, rad_to_deg(prev.angle_to(q)))
		prev = q
	check("moving crawl resumes the clip (speed_scale %.2f, limb peak %.0f deg)" % [ap.speed_scale, peak],
		ap.speed_scale > 0.0 and peak > 1.0)
	Input.action_release("move_forward")

	# 3. WALL JUMP: its own clip, played crisply.
	for i in 20:
		await physics_frame
	Input.action_press("jump")
	for i in 3:
		await physics_frame
	Input.action_release("jump")
	check("wall jump plays moves/wall_jump (%s, state %s)" % [ap.current_animation, p.STATE_NAMES[p.state]],
		p.state == PC.State.WALL_JUMP and ap.current_animation == "moves/wall_jump")
	for i in 60:
		await physics_frame

	# 4. WALL RUN: the run stride on the face, with the body's down into the surface. Sprint + W is
	#    the stable way in: the entry momentum alone bleeds off below the run threshold in a few frames.
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
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var saw_run := false
	var run_basis := Basis()
	var run_clip := ""
	var run_scale := 0.0
	var run_frames := 0
	for i in 40:
		await physics_frame
		run_frames = run_frames + 1 if p.state == PC.State.WALL_RUN else 0
		if run_frames == 12:  # the body frame needs ~0.2 s to swing from the crawl onto its feet
			saw_run = true
			run_basis = p.visual.global_transform.basis
			run_clip = ap.current_animation
			run_scale = ap.speed_scale
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check("fast entry reaches WALL RUN", saw_run)
	check("wall run plays the run stride (%s)" % run_clip, run_clip == "moves/run")
	check("wall run puts the body's down into the face (basis.y . n = %.3f)" % run_basis.y.dot(wall.normal),
		run_basis.y.dot(wall.normal) > 0.95)
	check("wall run keeps the stride rate (speed_scale %.2f)" % run_scale, run_scale >= 0.8)
	for i in 40:
		await physics_frame

	# 5. WALL EDGE UP: climbing the face onto the roof plays the mantle clip.
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	p.global_position = Vector3(38.6, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 15:
		await physics_frame
	Input.action_release("move_right")
	Input.action_press("move_forward")
	var up_clip := ""
	for i in 400:
		await physics_frame
		if p.state == PC.State.WALL_EDGE_UP:
			up_clip = ap.current_animation
			break
	Input.action_release("move_forward")
	check("wall edge up plays moves/wall_edge_up (%s)" % up_clip, up_clip == "moves/wall_edge_up")
	for i in 60:
		await physics_frame

	# 6. WALL EDGE DOWN: walking down the face to the floor plays the step-down clip.
	p.global_position = Vector3(30, 0.1, -22)
	p.velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	p.global_position = Vector3(38.5, 5.0, -22)
	p.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame
	Input.action_press("move_right")
	for i in 25:
		await physics_frame
	Input.action_release("move_right")
	Input.action_press("move_back")
	var down_clip := ""
	for i in 240:
		await physics_frame
		if p.state == PC.State.WALL_EDGE_DOWN:
			down_clip = ap.current_animation
			break
	Input.action_release("move_back")
	check("wall edge down plays moves/wall_edge_down (%s)" % down_clip, down_clip == "moves/wall_edge_down")
	for i in 60:
		await physics_frame

	# 7. Off the face the body stands back up (no leftover pitch or roll).
	var up_dot: float = p.visual.global_transform.basis.y.dot(Vector3.UP)
	check("body returns upright after leaving the face (basis.y . up = %.3f)" % up_dot, up_dot > 0.98)

	# 8. A slanted face tilts the body with it: the frame is built from the normal, not from world up.
	wall.phase = wall.Phase.RUN
	wall.normal = Vector3(-0.94, 0.34, 0.0).normalized()  # 20 deg off vertical
	wall.wall_vel = Vector3(0, 6.0, 0)
	var tilted: Basis = p._wall_frame()
	check("slanted face: body's down is the face normal (dot %.3f)" % tilted.y.dot(wall.normal), tilted.y.dot(wall.normal) > 0.999)
	check("slanted face: frame stays orthonormal (x.y %.3f, |y| %.3f)" % [tilted.x.dot(tilted.y), tilted.y.length()],
		absf(tilted.x.dot(tilted.y)) < 0.001 and absf(tilted.y.length() - 1.0) < 0.001)
	check("slanted face: chest follows travel along the face (dot %.3f)" % tilted.z.dot(
		(wall.wall_vel - wall.normal * wall.wall_vel.dot(wall.normal)).normalized()),
		tilted.z.dot((wall.wall_vel - wall.normal * wall.wall_vel.dot(wall.normal)).normalized()) > 0.999)
	wall.detach()

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
