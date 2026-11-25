extends Node3D
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
## Wall crawl / run on a vertical face.
## Attach: a short probe finds a wall in reach and the player is moving into it.
## Movement: W = up the wall, S = down, A/D = sideways along it, mapped to the wall frame so
## A/D always read as screen left/right while facing the face. Shift = wall run.
## Stay: every step the body is re-checked against the face and snapped back onto it, so it cannot
## drift off. Walking past an outer corner wraps onto the adjacent face instead of dropping.
## Exits: Space = wall jump, the top edge = a timed climb onto the roof, the floor = step down.

enum Phase { NONE, CRAWL, RUN }

const G := 9.8
const REACH := 1.0            # m, how far the attach probe looks
const CRAWL_SPEED := 3.5      # m/s, deliberate crawl speed on the wall
const RUN_SPEED := 7.5        # m/s, Shift + WASD wall run
const RUN_MIN := 6.0          # m/s, above this the state is WALL RUN
const RUN_G := 2.5            # m/s^2, reduced gravity while running (not a stone)
const PRESS := 0.8            # m/s, push into the wall so contact is kept
const JUMP_PUSH := 8.0        # m/s, wall jump away from the normal
const JUMP_UP := 8.0          # m/s, wall jump upward
const EDGE_PROBE := 3.0       # m, how far down to look for a roof at the top edge
const CONTACT_GAP := 0.10     # m, how far the body may drift off its resting gap before a pull
const SNAP_MAX := 0.30        # m, most the body may be pulled onto the face in one step
const GRIP_STOP := 40.0       # m/s^2, surface grip that kills leftover speed when input stops
const WRAP_STEP := 45.0       # deg, corner probe increments

var phase := Phase.NONE
var normal := Vector3.ZERO    # unit wall normal, points out of the wall
var right := Vector3.ZERO     # unit, horizontal along the wall, screen-right when facing it
var wall_vel := Vector3.ZERO  # velocity in the wall plane (no normal component)
var f_wall := Vector3.ZERO    # N, wall normal force (for the FBD)
var f_grip := Vector3.ZERO    # N, wall friction holding the body up
var rest_gap := 0.5           # m, body axis to face when touching (capsule radius from the body)


func active() -> bool:
	return phase != Phase.NONE


## Screen-right tangent for this face: the camera's right projected onto the wall plane.
## UP.cross(normal) is the same vector when looking straight at the face, and the fallback
## when the camera is edge-on. normal.cross(UP) is its negation and inverts A/D.
func _set_right(cam_right: Vector3) -> void:
	var r := cam_right - normal * cam_right.dot(normal)
	if r.length() < 0.2:
		r = Vector3.UP.cross(normal)
	right = r.normalized()


## Look for a vertical face within reach. Stores normal and returns true on a hit.
func probe(body: CharacterBody3D, cam_right: Vector3) -> bool:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 0.9
	var dirs: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var hv := Vector3(body.velocity.x, 0, body.velocity.z)
	if hv.length() > 0.5:
		dirs.append(hv.normalized())
	for d in dirs:
		var q := Layers.ray(from, from + d * REACH)
		q.exclude = [body.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.35:
			continue  # floor or ceiling, not a wall
		normal = n.normalized()
		_set_right(cam_right)
		return true
	return false


## Grab the wall, keeping whatever tangential momentum the body already has.
func attach(body: CharacterBody3D, cam_right: Vector3, sprint: bool) -> void:
	_set_right(cam_right)
	rest_gap = _radius(body)
	wall_vel = body.velocity - normal * body.velocity.dot(normal)
	phase = Phase.RUN if sprint or wall_vel.length() > RUN_MIN else Phase.CRAWL


func detach() -> void:
	phase = Phase.NONE
	wall_vel = Vector3.ZERO
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO


## Capsule radius of the body's first CollisionShape3D: the axis-to-face gap when touching.
func _radius(body: CharacterBody3D) -> float:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			return (c.shape as CapsuleShape3D).radius
	return 0.45


## Distance from the body axis to the face along -normal, INF when the face is gone.
func contact_dist(body: CharacterBody3D) -> float:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 0.9
	var q := Layers.ray(from, from - normal * (REACH + 0.5))
	q.exclude = [body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	if (hit["normal"] as Vector3).dot(normal) < 0.7:
		return INF  # a different face, not the one we are on
	return from.distance_to(hit["position"])


## Pull the body back onto the face. False when the face is out of reach.
func stick(body: CharacterBody3D) -> bool:
	var d := contact_dist(body)
	if d == INF:
		return false
	if d > rest_gap + CONTACT_GAP:
		body.global_position += -normal * minf(d - rest_gap, SNAP_MAX)
	return true


## Walking past an outer corner: probe from a point already around the edge and adopt the face
## found there. Returns the body position on the new face, or Vector3.INF when there is no corner.
## A ray from the body itself cannot see a perpendicular face past a convex corner, because the
## line to it passes through the corner region outside the face's own span.
func wrap(body: CharacterBody3D, cam_right: Vector3) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var base := body.global_position + Vector3.UP * 0.9
	# Try the way we are travelling first.
	var sides: Array[float] = [1.0, -1.0]
	if wall_vel.dot(right) < 0.0:
		sides = [-1.0, 1.0]
	for side in sides:
		var from := base + right * side * 0.6 - normal * (rest_gap + 0.25)
		for ang in [0.0, 45.0, -45.0, 90.0, -90.0]:
			var d := (-normal).rotated(Vector3.UP, deg_to_rad(ang))
			var q := Layers.ray(from, from + d * REACH)
			q.exclude = [body.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var n: Vector3 = hit["normal"]
			if absf(n.y) > 0.35 or n.dot(normal) > 0.7:
				continue  # floor, ceiling, or the face we are leaving
			normal = n.normalized()
			_set_right(cam_right)
			rest_gap = _radius(body)
			wall_vel = wall_vel - normal * wall_vel.dot(normal)  # drop speed into the new wall
			return Vector3(from.x, body.global_position.y, from.z)
	return Vector3.INF


## One step on the wall. Sets body.velocity. Returns "crawl", "run" or "jump".
func step(dt: float, body: CharacterBody3D, inp: Vector2, mass: float, jump: bool, sprint: bool, cam_right: Vector3) -> String:
	_set_right(cam_right)
	if jump:
		body.velocity = normal * JUMP_PUSH + Vector3.UP * JUMP_UP
		detach()
		return "jump"
	# Input in the wall frame: W climbs, S descends, A/D strafe. Never along the normal.
	var dir := right * inp.x + Vector3.UP * -inp.y
	var moving := dir.length() > 0.01
	if moving:
		dir = dir.normalized()
		var target := RUN_SPEED if sprint else CRAWL_SPEED
		if not sprint and wall_vel.length() > RUN_MIN:
			target = wall_vel.length()  # a momentum run keeps its speed
		wall_vel = wall_vel.lerp(dir * target, 1.0 - exp(-10.0 * dt))
	elif wall_vel.length() > RUN_MIN:
		wall_vel = wall_vel.move_toward(Vector3.ZERO, 6.0 * dt)  # no input: the run bleeds off
	if wall_vel.length() > RUN_MIN:
		wall_vel += Vector3.DOWN * RUN_G * dt  # reduced gravity: an arc, not a drop
	elif not moving:
		# Surface grip, only with no input: leftover drift dies fast so the body holds still.
		wall_vel = wall_vel.move_toward(Vector3.ZERO, GRIP_STOP * dt)
	body.velocity = wall_vel + (-normal) * PRESS  # press in so move_and_slide keeps contact
	# FBD: the press is the normal force, friction is what holds the body against gravity.
	f_wall = normal * (mass * PRESS / maxf(dt, 0.0001))
	f_grip = Vector3.UP * (mass * G)
	phase = Phase.RUN if (sprint and moving) or wall_vel.length() > RUN_MIN else Phase.CRAWL
	return "run" if phase == Phase.RUN else "crawl"


## Roof point above the head when the wall has ended, else Vector3.INF.
func top_edge(body: CharacterBody3D) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var head := body.global_position + Vector3.UP * 1.8
	var q := Layers.ray(head, head - normal * 1.2)
	q.exclude = [body.get_rid()]
	if not space.intersect_ray(q).is_empty():
		return Vector3.INF  # wall continues above the head
	var from := head + Vector3.UP * 0.5 - normal * 0.9
	var d := Layers.ray(from, from + Vector3.DOWN * EDGE_PROBE)
	d.exclude = [body.get_rid()]
	var hit := space.intersect_ray(d)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		return Vector3.INF
	return hit["position"]


## Where to stand once over the top: on the roof, a little in from the edge.
func roof_stand(roof: Vector3) -> Vector3:
	return roof + Vector3.UP * 0.05 - normal * 0.35
