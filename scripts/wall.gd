extends Node3D
## Wall crawl / run on a vertical face.
## Attach: a short probe finds a wall in reach and the player is moving into it.
## Movement: W = up the wall, S = down, A/D = sideways along it (the input is mapped to the wall
## frame, not the camera). Entering with speed keeps that tangential momentum, and a fast enough
## slide is a WALL RUN with reduced gravity.
## Exits: Space = wall jump, the top edge = climb onto the roof, the floor = step down.

enum Phase { NONE, CRAWL, RUN }

const G := 9.8
const REACH := 0.9            # m, how far the attach probe looks
const CRAWL_SPEED := 3.5      # m/s, deliberate crawl speed on the wall
const RUN_MIN := 6.0          # m/s, above this the state is WALL RUN
const RUN_G := 2.5            # m/s^2, reduced gravity while running (not a stone)
const PRESS := 0.8            # m/s, push into the wall so contact is kept
const JUMP_PUSH := 8.0        # m/s, wall jump away from the normal
const JUMP_UP := 8.0          # m/s, wall jump upward
const EDGE_PROBE := 3.0       # m, how far down to look for a roof at the top edge

var phase := Phase.NONE
var normal := Vector3.ZERO    # unit wall normal, points out of the wall
var right := Vector3.ZERO     # unit, horizontal along the wall
var wall_vel := Vector3.ZERO  # velocity in the wall plane (no normal component)
var f_wall := Vector3.ZERO    # N, wall normal force (for the FBD)
var f_grip := Vector3.ZERO    # N, wall friction holding the body up


func active() -> bool:
	return phase != Phase.NONE


## Look for a vertical face within reach. Stores normal/right and returns true on a hit.
func probe(body: CharacterBody3D) -> bool:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 0.9
	var dirs: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var hv := Vector3(body.velocity.x, 0, body.velocity.z)
	if hv.length() > 0.5:
		dirs.append(hv.normalized())
	for d in dirs:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * REACH)
		q.exclude = [body.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.35:
			continue  # floor or ceiling, not a wall
		normal = n.normalized()
		right = normal.cross(Vector3.UP).normalized()
		return true
	return false


## Grab the wall, keeping whatever tangential momentum the body already has.
func attach(body: CharacterBody3D) -> void:
	wall_vel = body.velocity - normal * body.velocity.dot(normal)
	phase = Phase.RUN if wall_vel.length() > RUN_MIN else Phase.CRAWL


func detach() -> void:
	phase = Phase.NONE
	wall_vel = Vector3.ZERO
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO


## One step on the wall. Sets body.velocity. Returns "crawl", "run" or "jump".
func step(dt: float, body: CharacterBody3D, inp: Vector2, mass: float, jump: bool) -> String:
	if jump:
		body.velocity = normal * JUMP_PUSH + Vector3.UP * JUMP_UP
		detach()
		return "jump"
	# Input in the wall frame: W climbs, S descends, A/D strafe. Never along the normal.
	var dir := right * inp.x + Vector3.UP * -inp.y
	var speed := wall_vel.length()
	if dir.length() > 0.01:
		dir = dir.normalized()
		if speed > RUN_MIN:
			wall_vel = dir * speed  # a run holds its speed along the input
		else:
			wall_vel = wall_vel.lerp(dir * CRAWL_SPEED, 1.0 - exp(-8.0 * dt))
	elif speed > RUN_MIN:
		wall_vel = wall_vel.move_toward(Vector3.ZERO, 6.0 * dt)  # no input: the run bleeds off
	if wall_vel.length() > RUN_MIN:
		wall_vel += Vector3.DOWN * RUN_G * dt  # reduced gravity: an arc, not a drop
	else:
		wall_vel.y = move_toward(wall_vel.y, 0.0, CRAWL_SPEED * 2.0 * dt)  # grip kills the drift
	body.velocity = wall_vel + (-normal) * PRESS  # press in so move_and_slide keeps contact
	# FBD: the press is the normal force, friction is what holds the body against gravity.
	f_wall = normal * (mass * PRESS / maxf(dt, 0.0001))
	f_grip = Vector3.UP * (mass * G)
	phase = Phase.RUN if wall_vel.length() > RUN_MIN else Phase.CRAWL
	return "run" if phase == Phase.RUN else "crawl"


## Roof point above the head when the wall has ended, else Vector3.INF.
func top_edge(body: CharacterBody3D) -> Vector3:
	var space := body.get_world_3d().direct_space_state
	var head := body.global_position + Vector3.UP * 1.8
	var q := PhysicsRayQueryParameters3D.create(head, head - normal * 1.2)
	q.exclude = [body.get_rid()]
	if not space.intersect_ray(q).is_empty():
		return Vector3.INF  # wall continues above the head
	var from := head + Vector3.UP * 0.5 - normal * 0.9
	var d := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * EDGE_PROBE)
	d.exclude = [body.get_rid()]
	var hit := space.intersect_ray(d)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		return Vector3.INF
	return hit["position"]


## Where to stand once over the top: on the roof, a little in from the edge.
func roof_stand(roof: Vector3) -> Vector3:
	return roof + Vector3.UP * 0.05 - normal * 0.35
