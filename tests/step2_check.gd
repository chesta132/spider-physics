extends SceneTree
## Step 2 checks: super jump charge, dive and fast dive, heavy-landing state.
## Run: godot --headless -s tests/step2_check.gd

const PC := preload("res://scripts/player_controller.gd")
var fails := 0
var main: Node
var p: CharacterBody3D


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


## Hold jump for hold_frames, release, then run until the body is back on the floor.
func jump(hold_frames: int, shift_in_dive: bool) -> Dictionary:
	var out := {"apex": 0.0, "dive_seen": false, "fast_seen": false, "dive_speed": 0.0,
		"peak_fn": 0.0, "land_state": false, "drag_loss": 0.0, "landed": false}
	var start_y := p.global_position.y
	Input.action_press("jump")
	for i in hold_frames:
		await physics_frame
	Input.action_release("jump")
	for i in 900:
		await physics_frame
		out.apex = maxf(out.apex, p.global_position.y - start_y)
		if shift_in_dive:
			if p.state == PC.State.DIVE or p.state == PC.State.FAST_DIVE:
				Input.action_press("fast_dive")
			else:
				Input.action_release("fast_dive")
		if p.state == PC.State.DIVE or p.state == PC.State.FAST_DIVE:
			out.dive_seen = true
			out.dive_speed = maxf(out.dive_speed, -p.velocity.y)
		if p.state == PC.State.FAST_DIVE:
			out.fast_seen = true
		out.peak_fn = maxf(out.peak_fn, maxf(p.f_n.length(), p.impact_force))
		if p.state == PC.State.LAND:
			out.land_state = true
		if out.apex > 0.3 and p.is_on_floor():
			out.landed = true
			out.drag_loss = p.drag_loss
			break
	Input.action_release("fast_dive")
	for i in 60:  # let the body settle before the next jump
		await physics_frame
	return out


func _initialize() -> void:
	check("super height 1.2 m at zero charge", absf(PC.super_height(0.0) - 1.2) < 1e-6)
	check("super height 10 m at full charge", absf(PC.super_height(1.0) - 10.0) < 1e-6)
	check("fast dive drag below normal drag", PC.DRAG_K_FAST < PC.DRAG_K)
	check("fast dive terminal speed above normal", sqrt(PC.MASS * PC.G / PC.DRAG_K_FAST) > sqrt(PC.MASS * PC.G / PC.DRAG_K))
	check("LAND state has its own color", PC.STATE_COLORS[PC.State.LAND] != PC.STATE_COLORS[PC.State.WALK])

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	p = main.get_node("Player")
	for i in 120:
		await physics_frame

	var tap: Dictionary = await jump(3, false)
	check("tap jump apex 1.2 m (got %.2f)" % tap.apex, absf(tap.apex - PC.JUMP_HEIGHT) < 0.15)
	check("tap jump does not enter LAND (drop under %.1f m)" % PC.LAND_DROP, not tap.land_state)

	var sup: Dictionary = await jump(60, false)
	print("super apex %.2f m, dive speed %.2f m/s, peak F_N %.0f N, drag loss %.0f J, LAND %s" % [sup.apex, sup.dive_speed, sup.peak_fn, sup.drag_loss, sup.land_state])
	check("full-charge super jump apex ~10 m (got %.2f)" % sup.apex, absf(sup.apex - PC.SUPER_HEIGHT) < 1.5)
	check("super jump enters DIVE after 2 m drop", sup.dive_seen)
	check("super jump lands on floor", sup.landed)
	check("heavy landing enters LAND state", sup.land_state)
	check("heavy landing measured peak F_N above 2x weight (got %.0f N)" % sup.peak_fn, sup.peak_fn > 2.0 * PC.MASS * PC.G)
	check("air drag removed energy during fall (%.0f J)" % sup.drag_loss, sup.drag_loss > 0.0)

	var fast: Dictionary = await jump(60, true)
	print("fast dive speed %.2f m/s vs normal %.2f m/s" % [fast.dive_speed, sup.dive_speed])
	check("holding Shift in dive reaches FAST DIVE", fast.fast_seen)
	check("fast dive reaches higher speed than normal dive", fast.dive_speed > sup.dive_speed)

	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails else 0)
