extends SceneTree
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
## Step 6 checks: the real city map and the rigged player model are wired in and still playable.
## Verifies baked collision exists, the player spawns on a street, wall crawl attaches to a real
## building with an outward normal, perch hints appear on real rooftops, and the model is fitted
## to the 1.8 m capsule with feet at y=0 and its face along +Z.
## Run: godot --headless -s tests/step6_check.gd

var fails := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)  # map_scene is set in the scene: this loads the city
	var p: CharacterBody3D = main.get_node("Player")
	for i in 90:
		await physics_frame

	var map: Node = main.get_node("Greybox/MapCity")
	var bodies := _count(map, "StaticBody3D")
	check("map instanced under Greybox", map != null)
	check("collision baked for the map (%d bodies)" % bodies, bodies > 4000)

	# 1. Spawn: on the street the map's Spawn marker points at, standing on real ground.
	check("player spawned at the map Spawn marker (%.2f, %.2f, %.2f)" % [
		p.global_position.x, p.global_position.y, p.global_position.z],
		p.global_position.length() < 3.0)
	check("player is on the ground (y %.3f, on_floor %s)" % [p.global_position.y, p.is_on_floor()],
		p.is_on_floor() and absf(p.global_position.y) < 0.3)
	var down := PhysicsRayQueryParameters3D.create(
		p.global_position + Vector3.UP, p.global_position + Vector3.DOWN * 3.0)
	down.exclude = [p.get_rid()]
	var gh: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(down)
	check("street surface is a real collider (normal.y %.2f)" % [gh.get("normal", Vector3.ZERO).y],
		not gh.is_empty() and (gh["normal"] as Vector3).y > 0.8)

	# 1b. World boundary: a shell the player hits, that no gameplay ray can see.
	var sp := p.get_world_3d().direct_space_state
	var bnd: Node3D = map.get_node("WorldBoundary")
	var shells: Array = []
	for c in bnd.get_children():
		if c is StaticBody3D:
			shells.append(c)
	check("boundary shell built (%d boxes)" % shells.size(), shells.size() >= 5)
	check("boundary sits on its own layer",
		not shells.is_empty() and (shells[0] as StaticBody3D).collision_layer == Layers.BOUNDARY)
	check("player collides with the boundary (mask %d)" % p.collision_mask,
		(p.collision_mask & Layers.BOUNDARY) != 0)

	# The shell must enclose the map: four rays from above the city hit it in every direction,
	# while a gameplay ray (WORLD mask) passes straight through.
	var high := Vector3(0, 170, 0)  # above the tallest building (150 m), below the shell top
	var enclosed := 0
	var leaked := 0
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var all_hit: Dictionary = sp.intersect_ray(PhysicsRayQueryParameters3D.create(high, high + d * 1500.0))
		if not all_hit.is_empty() and (all_hit["collider"] as CollisionObject3D).collision_layer == Layers.BOUNDARY:
			enclosed += 1
		var world_hit: Dictionary = sp.intersect_ray(Layers.ray(high, high + d * 1500.0))
		if not world_hit.is_empty() and (world_hit["collider"] as CollisionObject3D).collision_layer == Layers.BOUNDARY:
			leaked += 1
	check("boundary encloses the map on all four sides (%d/4)" % enclosed, enclosed == 4)
	check("no gameplay ray can see the boundary (%d/4 leaked)" % leaked, leaked == 0)

	# Standing outside the shell, aimed straight at it: web and zip must find nothing.
	var wall_c: Vector3 = (shells[0] as StaticBody3D).global_position
	var x0: float = wall_c.x - 13.0
	p.global_position = Vector3(x0, 4.0, wall_c.z)
	p.velocity = Vector3.ZERO
	var pivot_b: Node3D = p.get_node("Pivot")
	pivot_b.set("yaw", -PI * 0.5)  # camera forward = +X, straight at the shell
	pivot_b.set("pitch", 0.0)
	for i in 4:
		await process_frame
	var cam_b: Camera3D = p.get_node("Pivot/Pitch/Arm/Camera")
	var wl: Node3D = p.get_node("WebLeft")
	var zn: Node3D = p.get_node("Zip")
	check("web refuses to anchor to the boundary", not wl.fire(cam_b, p.get_rid()))
	check("zip refuses to boost off the boundary",
		not zn.start_surface_boost(cam_b, p.get_rid(), p.global_position, p.velocity))

	# Drive into the shell: the body must stop at it, not cross it.
	p.velocity = Vector3(25.0, 0, 0)
	for i in 90:
		await physics_frame
	check("the boundary stops a body crossing it (x %.1f, shell face %.1f)" % [
		p.global_position.x, wall_c.x - 2.0],
		p.global_position.x > x0 + 5.0 and p.global_position.x < wall_c.x - 1.5)

	p.global_position = Vector3(0, 0.05, 0)  # back to the spawn for the wall-crawl checks
	p.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame

	# 2. Wall crawl on a real building: pick the nearest vertical face and walk into it.
	var space := p.get_world_3d().direct_space_state
	var wall: Node = p.get_node("Wall")
	var face := Vector3.ZERO
	var face_n := Vector3.ZERO
	var faces: Array = []  # [surface point, normal]
	for i in 24:
		var a := TAU * float(i) / 24.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.2,
			p.global_position + Vector3.UP * 1.2 + dir * 40.0)
		q.exclude = [p.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var d: float = p.global_position.distance_to(hit["position"])
		if absf(n.y) < 0.35 and d > 4.0 and d < 30.0 and n.dot(-dir) > 0.8:
			faces.append([hit["position"], n])
	check("found vertical building faces near the spawn (%d)" % faces.size(), faces.size() >= 4)

	# Facades carry ledges and awnings that wedge a capsule, so crawl where the column above is clear.
	for f in faces:
		var strip_y := _clear_strip(space, f[0], f[1])
		if strip_y < 0.0:
			continue
		face = Vector3(f[0].x, strip_y, f[0].z)
		face_n = f[1]
		break
	check("found a clean stretch of facade to crawl", face_n != Vector3.ZERO and face.y > 0.0)

	if face_n != Vector3.ZERO:
		p.global_position = face + face_n * 0.6
		p.velocity = Vector3.ZERO
		p.set("watching", false)
		var pivot: Node3D = p.get_node("Pivot")
		pivot.set("yaw", atan2(face_n.x, face_n.z))  # camera forward = into the wall
		pivot.set("pitch", 0.2)
		for i in 5:
			await physics_frame
		Input.action_press("move_forward")
		for i in 40:
			await physics_frame
		check("moving into a real building attaches", wall.active())
		check("attached normal matches the face (dot %.2f)" % wall.normal.dot(face_n), wall.normal.dot(face_n) > 0.9)
		check("body is not pulled through the wall", (p.global_position - face).dot(face_n) > -0.1)
		var y0: float = p.global_position.y
		for i in 60:
			await physics_frame
		Input.action_release("move_forward")
		check("W climbs the real wall (%.2f m)" % (p.global_position.y - y0), p.global_position.y - y0 > 1.5)
		if wall.active():
			wall.detach()

	# 3. Perch hints: sweep the camera until the zip reticle finds a real rooftop edge.
	for i in 30:
		await physics_frame
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	var zip: Node = p.get_node("Zip")
	var pivot2: Node3D = p.get_node("Pivot")
	var found := false
	for yi in 24:
		for pd in [8.0, 20.0, 32.0]:
			pivot2.set("yaw", deg_to_rad(yi * 15.0))
			pivot2.set("pitch", deg_to_rad(pd))
			await process_frame
			await physics_frame
			if zip.has_perch:
				found = true
				break
		if found:
			break
	check("perch hint found on a real rooftop edge", found)

	# 4. Player model: fitted to the capsule, feet on the floor, facing +Z.
	var model: Node3D = p.get_node("Visual/Model")
	check("model instanced under Visual", model != null)
	var sk := _find_skeleton(model)
	check("model has a skeleton", sk != null)
	if sk != null:
		(p.get_node("Visual") as Node3D).rotation.y = 0.0  # measuring the rig, not the current heading
		await process_frame
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := -lo
		var toe_z := 0.0
		var foot_z := 0.0
		for i in sk.get_bone_count():
			var bn: String = sk.get_bone_name(i)
			if bn.begins_with("_"):
				continue  # _rootJoint is a rig artefact parked 2 m off the body
			var b: Transform3D = sk.global_transform * sk.get_bone_global_rest(i)  # bone rest is skeleton-local
			var o: Vector3 = b.origin - p.global_position  # player-local, so the street offset cancels
			lo = lo.min(o)
			hi = hi.max(o)
			if bn.contains("ToeBase") and not bn.contains("end"):
				toe_z = o.z
			elif bn.contains("Foot"):
				foot_z = o.z
		var h: float = hi.y - lo.y
		check("model stands 1.8 m tall (%.3f m)" % h, h > 1.7 and h < 1.9)
		check("model feet sit on the body origin (%.3f m)" % lo.y, absf(lo.y) < 0.06)
		check("model is centred on the capsule axis (x %.3f, z %.3f)" % [(lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5],
			absf((lo.x + hi.x) * 0.5) < 0.12 and absf((lo.z + hi.z) * 0.5) < 0.12)
		check("model faces +Z (toe %.2f > heel %.2f)" % [toe_z, foot_z], toe_z > foot_z)

	# 5. F3 overlay and the state label survived the swap.
	check("F3 physics HUD still present", p.get_node_or_null("PhysicsHUD") != null)
	check("state label still present", p.get_node_or_null("StateLabel") != null)

	print("\n%d fail(s)" % fails)
	quit(1 if fails > 0 else 0)


## Lowest height where a 3 m column just off the face is empty and the face is still there 8 m
## further up: a plain stretch of facade a capsule can crawl without catching a ledge — and tall
## enough that the top-edge climb-over does not cut the crawl short.
func _clear_strip(space: PhysicsDirectSpaceState3D, face: Vector3, n: Vector3) -> float:
	var off := face + n * 0.75
	for h in range(2, 40):
		var a := Vector3(off.x, float(h), off.z)
		var up := PhysicsRayQueryParameters3D.create(a, a + Vector3.UP * 3.0)
		if not space.intersect_ray(up).is_empty():
			continue
		var high := a + Vector3.UP * 8.0
		var q := PhysicsRayQueryParameters3D.create(high, high - n * 1.5)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty() and (hit["normal"] as Vector3).dot(n) > 0.9:
			return float(h)
	return -1.0


func _count(n: Node, cls: String) -> int:
	var c := 1 if n.is_class(cls) else 0
	for ch in n.get_children():
		c += _count(ch, cls)
	return c


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null