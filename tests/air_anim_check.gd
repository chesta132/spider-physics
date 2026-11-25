extends SceneTree
## Air-state animation and landing-impact check. Physics is driven by the existing controller.
var fails := 0

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func sk_pose(p: Node, bone: String) -> Vector3:
	var sk: Skeleton3D = p.get_node("Visual/Model/Rig/Skeleton")
	return sk.get_bone_pose_rotation(sk.find_bone(bone)).get_euler()


## Lowest world y of the drawn mesh at the current pose: the ground-contact check.
func lowest_mesh_y(p: Node) -> float:
	var mi: MeshInstance3D = p.get_node("Visual/Model/Rig/Skeleton/Body")
	var sk: Skeleton3D = p.get_node("Visual/Model/Rig/Skeleton")
	var skin := mi.skin
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / verts.size()
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		mats.append(sk.get_bone_global_pose(sk.find_bone(skin.get_bind_name(i))) * skin.get_bind_pose(i))
	var lo := 1e9
	for v in verts.size():
		var q := Vector3.ZERO
		var ws := 0.0
		for k in stride:
			var w: float = wts[v * stride + k]
			if w > 0.0:
				q += (mats[bones[v * stride + k]] * verts[v]) * w
				ws += w
		if ws > 0.0:
			lo = minf(lo, (p.get_node("Visual/Model/Rig/Skeleton").global_transform * (q / ws)).y)
	return lo


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
	# Let the 0.10 s impact crossfade finish before measuring the held pose.
	for i in 25:
		await physics_frame
	# The landing must read as the reference silhouette, not a symmetric squat.
	var thL := rad_to_deg(sk_pose(p, "Thigh.L").x)
	var thR := rad_to_deg(sk_pose(p, "Thigh.R").x)
	var knL := rad_to_deg(sk_pose(p, "LowerLeg.L").x)
	var knR := rad_to_deg(sk_pose(p, "LowerLeg.R").x)
	var torso := rad_to_deg(sk_pose(p, "Torso").x)
	var open_arm := rad_to_deg(sk_pose(p, "UpperArm.L").z)
	var plant_arm := rad_to_deg(sk_pose(p, "UpperArm.R").x)
	check("torso pitched forward (%.0f deg)" % torso, torso > 60.0)
	check("support leg folded (knee %.0f deg), wide leg straight (knee %.0f deg)" % [knL, knR], knL > 80.0 and knR < 25.0)
	check("legs asymmetric (thigh %.0f vs %.0f deg)" % [thL, thR], absf(thL - thR) > 30.0)
	check("arms asymmetric: open %.0f deg out, planted %.0f deg down" % [open_arm, plant_arm], open_arm > 55.0 and plant_arm < -35.0)
	var hips_y: float = p.get_node("Visual/Model/Rig/Skeleton").get_bone_global_pose(
		p.get_node("Visual/Model/Rig/Skeleton").find_bone("Hips")).origin.y
	check("hips dropped toward the street (%.3f m, rest 0.648)" % hips_y, hips_y < 0.56)
	var low := lowest_mesh_y(p)
	check("landing mesh sits on the street (lowest vertex %+.3f m)" % low, absf(low) < 0.02)
	# Head must stay seated on the neck joint (no float) and still look forward.
	var skn: Skeleton3D = p.get_node("Visual/Model/Rig/Skeleton")
	var neck := (skn.get_bone_global_pose(skn.find_bone("Head")).origin - skn.get_bone_global_pose(skn.find_bone("Torso")).origin).length()
	var rest_neck := (skn.get_bone_global_rest(skn.find_bone("Head")).origin - skn.get_bone_global_rest(skn.find_bone("Torso")).origin).length()
	check("head seated on the neck (gap %.3f vs rest %.3f)" % [neck, rest_neck], absf(neck - rest_neck) < 0.005)
	var face := rad_to_deg(Vector3.UP.angle_to(skn.get_bone_global_pose(skn.find_bone("Head")).basis.y))
	check("head still looks forward (%.0f deg from upright)" % face, face < 30.0)
	# Planted hand must reach AHEAD of the hips, not hang at the side.
	var hips := skn.get_bone_global_pose(skn.find_bone("Hips")).origin
	var hand := skn.get_bone_global_pose(skn.find_bone("Hand.R")).origin
	check("planted hand reaches forward (+%.3f m ahead of hips)" % (hand.z - hips.z), hand.z - hips.z > 0.25)
	check("planted hand is outside the body (|x| %.3f)" % absf(hand.x), absf(hand.x) > 0.45)
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
