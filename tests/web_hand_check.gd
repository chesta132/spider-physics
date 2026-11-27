extends SceneTree
## Web attachment + lean checks: strands start at the rig's Hand.L / Hand.R bones, a missing rig or
## bone falls back to a shoulder point instead of breaking, and the cosmetic body leans along the
## live web while swinging / zipping and eases upright again on release.
## Run: godot --headless -s tests/web_hand_check.gd

const Hands := preload("res://scripts/hands.gd")
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


## Near end of a _seg() box: the segment runs -Z..+Z through its centre, so the start is
## centre - basis.z * 0.5 (basis.z already carries the length).
func seg_start(mi: MeshInstance3D) -> Vector3:
	var x := mi.global_transform
	return x.origin - x.basis.z * 0.5


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("map_scene", null)  # these checks pin greybox geometry
	root.add_child(main)
	var p: CharacterBody3D = main.get_node("Player")
	for i in 120:
		await physics_frame
	var wl = p.get_node("WebLeft")
	var wr = p.get_node("WebRight")
	var cam: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")
	var sk: Skeleton3D = p.get_node("Visual/Model/Rig/Skeleton")
	var vis: Node3D = p.get_node("Visual")
	var model: Node3D = p.get_node("Visual/Model")

	# 1. Sockets resolve to the real bones, one per side, on the correct side of the body.
	var hands := Hands.new(p)
	var hl := hands.point(-1.0)
	var hr := hands.point(1.0)
	var bl: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hand.L")).origin
	var br: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hand.R")).origin
	check("left socket is the Hand.L bone (%.3f m off)" % hl.distance_to(bl), hl.distance_to(bl) < 0.005)
	check("right socket is the Hand.R bone (%.3f m off)" % hr.distance_to(br), hr.distance_to(br) < 0.005)
	check("the two hands are separate points (%.2f m apart)" % hl.distance_to(hr), hl.distance_to(hr) > 0.3)
	# The rig faces +Z, so its own left hand sits at local +X and the right at -X.
	var inv := vis.global_transform.affine_inverse()
	var lx := (inv * hl).x
	var rx := (inv * hr).x
	check("Hand.L is the rig's left side (local x %+.2f), Hand.R the right (%+.2f)" % [lx, rx],
		lx > 0.1 and rx < -0.1)

	# 2. Safe fallbacks: no rig at all, then a skeleton with no hand bones. No errors, no zeros.
	var bare := Node3D.new()
	var bare_vis := Node3D.new()
	bare_vis.name = "Visual"
	bare.add_child(bare_vis)
	root.add_child(bare)
	bare.global_position = Vector3(5, 0, 5)
	bare_vis.rotation.y = PI * 0.5
	var bare_hands := Hands.new(bare)
	var fp := bare_hands.point(1.0)
	var want: Vector3 = bare_vis.global_transform * Vector3(0.36, 1.35, 0.10)
	check("no rig: fallback at shoulder height in the visual frame (%.2f, %.2f, %.2f)" % [fp.x, fp.y, fp.z],
		fp.distance_to(want) < 0.01)
	var skel_only := Skeleton3D.new()
	bare.add_child(skel_only)
	var skel_hands := Hands.new(bare)
	check("skeleton without hand bones: same fallback, no error",
		skel_hands.point(-1.0).distance_to(bare_hands.point(-1.0)) < 0.01)
	var orphan := Hands.new(null)
	check("no player at all: still a finite point", orphan.point(1.0).is_finite())

	# 3. Live swing: both strands leave their own hand, and they stay on opposite sides.
	cam.rotation.x = -0.4
	cam.rotation.y = 0.0
	p.get_node("Visual/Model/Rig/AnimationPlayer").stop()  # freeze the pose so the sockets are fixed
	check("left web attaches", wl.fire(cam, p.get_rid()))
	for i in 25:
		await physics_frame  # early in the swing the anchor is well above the body
	var early_pitch: float = model.rotation.x
	check("body pitches toward an anchor above it (%.1f deg)" % rad_to_deg(early_pitch),
		early_pitch > deg_to_rad(5.0) and early_pitch < deg_to_rad(56.0))
	check("right web attaches", wr.fire(cam, p.get_rid()))
	for i in 65:
		await physics_frame
	check("both webs hold the rope (%s / %s)" % [wl.phase, wr.phase],
		wl.phase == wl.Phase.ROPE and wr.phase == wr.Phase.ROPE)
	await physics_frame
	var ap: AnimationPlayer = p.get_node("Visual/Model/Rig/AnimationPlayer")
	check("two-web swing animation selected", ap.current_animation == "moves/swing_up_2" or ap.current_animation == "moves/swing_down_2")
	check("two-web animation has minimal beat keys", ap.get_animation(ap.current_animation).track_get_key_count(0) == 3)
	await process_frame
	await process_frame
	var sl := seg_start(wl._line)
	var sr := seg_start(wr._line)
	check("left strand starts at the left hand (%.3f m off)" % sl.distance_to(hands.point(-1.0)),
		sl.distance_to(hands.point(-1.0)) < 0.15)
	check("right strand starts at the right hand (%.3f m off)" % sr.distance_to(hands.point(1.0)),
		sr.distance_to(hands.point(1.0)) < 0.15)
	check("strands are not both on the body centre (%.2f m apart)" % sl.distance_to(sr), sl.distance_to(sr) > 0.3)

	# 4. Lean: pitched along the rope (forward or back with the arc), banked by the side it is on.
	var lean_pitch: float = model.rotation.x
	var lean_roll: float = model.rotation.z
	check("model follows the lean state (%.2f vs %.2f deg)" % [rad_to_deg(lean_pitch), rad_to_deg(p.lean_pitch)],
		absf(lean_pitch - p.lean_pitch) < 0.01)
	check("body is still leaning mid-swing (%.1f deg)" % rad_to_deg(lean_pitch), absf(lean_pitch) > deg_to_rad(2.0))
	check("lean stays inside the bank limit (%.1f deg)" % rad_to_deg(lean_roll), absf(lean_roll) <= deg_to_rad(25.5))
	check("lean pivots at the hips, not the feet (model y %.2f)" % model.position.y, absf(model.position.y) < 0.6)
	check("physics body is still upright (rotation %s)" % p.rotation, p.rotation.is_zero_approx())

	# 5. Release: the lean blends back to exactly upright, and the strands keep falling.
	wl.release(Vector3(0, 0, -1), p.velocity.length())
	wr.release(Vector3(0, 0, -1), p.velocity.length())
	for i in 120:
		await physics_frame
	check("lean returns to upright (%.2f deg)" % rad_to_deg(model.rotation.x), absf(model.rotation.x) < 0.01)
	check("model transform is exactly identity when no web is up", model.transform.is_equal_approx(Transform3D.IDENTITY))

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
