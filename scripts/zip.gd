extends Node3D
## Zip to point, two modes:
##  - Perch: a rooftop edge / outer corner is under the reticle, so Ctrl zips the body onto it and
##    the controller settles into Watching.
##  - Boost: no perch in view, so Ctrl fires a quick forward web and yanks the body along it,
##    detaching at once and leaving the strand to fall.
## Only real geometry counts; empty sky never does.

const G := 9.8
enum Phase { IDLE, SHOOT, PULL }

const RANGE := 45.0                     # m, longest zip
const MIN_DIST := 3.0                   # m, closer hits are ignored (already there)
const SHOOT_TIME := 0.08                # s, line travel to the target
const ZIP_SPEED := 26.0                 # m/s, pull speed along the path
const ARRIVE_DIST := 1.7                # m, arrival radius
const VAULT_FWD := 6.0                  # m/s, Space near arrival: forward
const VAULT_UP := 7.5                   # m/s, Space near arrival: up
const STRAND_TIME := 2.0                # s, released strand lifetime
const STRAND_DRAG := 0.4                # 1/s

# Perch search: top faces only, and only near a drop (outer edge / corner)
const PERCH_MIN_DIST := 4.0
const PERCH_MAX_DIST := 40.0
const PERCH_EDGE_PROBE := 0.6           # m, how far out to look for a drop
const PERCH_EDGE_DROP := 0.8            # m, a probe must fall this far to count as an edge
const PERCH_HINT_HZ := 12.0             # hint refresh rate (rays are cheap but not free)

# Forward boost (no perch in view)
const DASH_KICK := 12.0                 # m/s, speed added by an air dash along the camera direction
const DASH_LINE_TIME := 0.2             # s, how long a dash shows its web line when a surface is hit
const BOOST_LIFT := 0.18                # upward fraction of the boost direction

var phase := Phase.IDLE
var mode := ""                          # "perch" | "boost"
var target := Vector3.ZERO
var target_normal := Vector3.UP
var perch := Vector3.ZERO               # best perch under the reticle
var perch_outward := Vector3.FORWARD    # horizontal direction away from the building edge
var has_perch := false
var shoot_from := Vector3.ZERO
var shoot_t := 0.0
var tip := Vector3.ZERO
var dash_line_t := 0.0                  # s, how long a dash shows its web line
var dash_from := Vector3.ZERO
var dash_hit := Vector3.ZERO
var dash_has_hit := false
var f_zip := Vector3.ZERO               # N, pull force this tick (for the FBD)
var work := 0.0                         # J, work done by the pull
var impulse := Vector3.ZERO             # N s, total impulse from the pull
var start_pos := Vector3.ZERO
var start_speed := 0.0
var last_displacement := Vector3.ZERO
var last_dk := 0.0
var last_du := 0.0
var last_arrival := ""                  # "perch" | "vault" | "boost"
var arrive_vel := Vector3.ZERO          # velocity handed back on a vault
var strand_t := 0.0
var strand_anchor := Vector3.ZERO
var strand_tip := Vector3.ZERO
var strand_vel := Vector3.ZERO

var _line: MeshInstance3D
var _strand: MeshInstance3D
var _reticle: MeshInstance3D
var _hint_t := 0.0
var _body_rid: RID


func _ready() -> void:
	_body_rid = (get_parent() as CharacterBody3D).get_rid()  # so the perch hint works before the first zip
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 1.0, 1.0)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)
	box.material = m
	var ring := TorusMesh.new()
	ring.inner_radius = 0.3
	ring.outer_radius = 0.42
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.2, 1.0, 0.9)
	ring.material = rm
	_line = _make(box)
	_strand = _make(box)
	_reticle = _make(ring)
	_line.visible = false
	_strand.visible = false
	_reticle.visible = false


func _make(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	add_child(mi)
	return mi


## Search the view for a rooftop edge or outer corner. True when one is under the reticle.
func find_perch(cam: Camera3D, body_rid: RID) -> bool:
	_body_rid = body_rid
	var space := get_world_3d().direct_space_state
	var origin := cam.global_position
	var b := cam.global_transform.basis
	var fwd := -b.z
	var best := Vector3.ZERO
	var best_sc := -1e9
	for ix in range(-2, 3):
		for iy in range(-2, 3):
			var dir: Vector3 = (fwd + b.x * (ix * 0.07) + b.y * (iy * 0.07)).normalized()
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
			q.exclude = [body_rid]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var n: Vector3 = hit["normal"]
			var p: Vector3 = hit["position"]
			if n.y < 0.6:
				var top := _top_above(p, n, body_rid)
				if top == Vector3.INF:
					continue
				p = top
				n = Vector3.UP
			var d := origin.distance_to(p)
			if d < PERCH_MIN_DIST or d > PERCH_MAX_DIST:
				continue
			if not _is_edge(p, n, body_rid):
				continue
			var outward := _edge_outward(p, n, body_rid)
			var sc := p.y * 0.35 - d * 0.6 - absf(ix) * 0.4 - absf(iy) * 0.4  # close, high, near the reticle centre
			if sc > best_sc:
				best_sc = sc
				best = p
				perch_outward = outward
	has_perch = best_sc != -1e9
	if has_perch:
		perch = best
	return has_perch


## Roof above a wall hit: drop a ray from above a point just inside the building, so its first hit is the roof top.
func _top_above(p: Vector3, n: Vector3, body_rid: RID) -> Vector3:
	var space := get_world_3d().direct_space_state
	var inside := p - n * 0.2
	var q := PhysicsRayQueryParameters3D.create(inside + Vector3.UP * 40.0, inside + Vector3.DOWN * 0.5)
	q.exclude = [body_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var top: Vector3 = hit["position"]
	return top if top.y > p.y + 0.5 else Vector3.INF


## Find the horizontal direction from the edge out over the drop.
func _edge_outward(p: Vector3, n: Vector3, body_rid: RID) -> Vector3:
	var t1 := Vector3.RIGHT if absf(n.z) > 0.5 else Vector3.FORWARD
	t1 = (t1 - n * t1.dot(n)).normalized()
	var t2 := n.cross(t1)
	for dir in [t1, -t1, t2, -t2]:
		var from: Vector3 = p + dir * PERCH_EDGE_PROBE + n * 0.05
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
		q.exclude = [body_rid]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).y < p.y - PERCH_EDGE_DROP:
			return dir.normalized()
	return t1


## True when the surface point is within PERCH_EDGE_PROBE of a drop: an outer edge or corner.
func _is_edge(p: Vector3, n: Vector3, body_rid: RID) -> bool:
	var space := get_world_3d().direct_space_state
	var t1 := Vector3.RIGHT if absf(n.z) > 0.5 else Vector3.FORWARD
	t1 = (t1 - n * t1.dot(n)).normalized()
	var t2 := n.cross(t1)
	for dir in [t1, -t1, t2, -t2]:
		var from: Vector3 = p + dir * PERCH_EDGE_PROBE + n * 0.05
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0)
		q.exclude = [body_rid]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).y < p.y - PERCH_EDGE_DROP:
			return true  # the roof ends here
	return false


## Zip to the current perch. False when there is no perch hint.
func start_perch(cam: Camera3D, body_rid: RID, body_pos: Vector3, body_vel: Vector3) -> bool:
	if not find_perch(cam, body_rid):
		return false
	mode = "perch"
	target = perch
	target_normal = Vector3.UP
	shoot_from = body_pos + Vector3(0, 1.4, 0)
	tip = shoot_from
	shoot_t = 0.0
	start_pos = body_pos
	start_speed = body_vel.length()
	work = 0.0
	impulse = Vector3.ZERO
	f_zip = Vector3.ZERO
	phase = Phase.SHOOT
	return true


## No perch in view: a forward air dash, an impulse along the camera direction. No web is fired.
## The web line is drawn only when a real surface lies along the dash. It is visual and never attaches.
func start_dash(cam_fwd: Vector3, body: CharacterBody3D, mass: float) -> bool:
	var dir := (cam_fwd + Vector3.UP * BOOST_LIFT).normalized()
	var v0 := body.velocity
	var v1 := v0 + dir * DASH_KICK
	body.velocity = v1
	mode = "dash"
	last_arrival = "dash"
	impulse = mass * (v1 - v0)  # Ch.6: J = dp
	start_pos = body.global_position
	start_speed = v0.length()
	last_dk = 0.5 * mass * (v1.length_squared() - v0.length_squared())
	last_du = 0.0
	work = last_dk  # Ch.6: W = dK, the dash has no height change
	last_displacement = Vector3.ZERO
	f_zip = Vector3.ZERO
	var from := body.global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	dash_has_hit = not hit.is_empty() and from.distance_to(hit["position"]) >= MIN_DIST
	dash_line_t = DASH_LINE_TIME if dash_has_hit else 0.0
	if dash_has_hit:
		dash_from = from
		dash_hit = hit["position"]
	return true


## Advance the zip. Returns "pull", "perched", "vault", "boosted" or "idle".
func step(dt: float, body: CharacterBody3D, mass: float, vault: bool) -> String:
	_strand_step(dt)
	if phase == Phase.SHOOT:
		shoot_t += dt
		var f := minf(shoot_t / SHOOT_TIME, 1.0)
		tip = shoot_from.lerp(target, f)
		if f >= 1.0:
			phase = Phase.PULL
		return "pull"
	if phase != Phase.PULL:
		return "idle"
	var d := target - body.global_position
	var dist := d.length()
	if dist <= ARRIVE_DIST:
		return _finish(body, mass, vault)
	var dir := d / dist
	var speed := minf(ZIP_SPEED, dist / maxf(dt, 0.0001))  # never overshoot the target in one step
	var want := dir * speed
	var dv := want - body.velocity
	f_zip = mass * dv / maxf(dt, 0.0001)
	impulse += f_zip * dt
	body.velocity = want
	# Work-energy theorem (Ch. 6): the web does W = dK + dU_g. A kinematic pull has ~zero
	# per-tick force once it reaches speed, so F.dr per step would read 0.
	work = 0.5 * mass * (want.length_squared() - start_speed * start_speed) \
		+ mass * G * (body.global_position.y - start_pos.y)
	return "pull"


func _finish(body: CharacterBody3D, mass: float, vault: bool) -> String:
	last_displacement = body.global_position - start_pos
	last_dk = 0.5 * mass * (body.velocity.length_squared() - start_speed * start_speed)
	last_du = mass * G * last_displacement.y
	work = last_dk + last_du  # exact at the arrival point
	_detach(body.global_position)
	f_zip = Vector3.ZERO
	phase = Phase.IDLE
	if vault:
		arrive_vel = body.velocity.normalized() * VAULT_FWD + Vector3.UP * VAULT_UP
		last_arrival = "vault"
		return "vault"
	last_arrival = "perch"
	return "perched"


## Perch placement: feet on the surface point, velocity cleared by the controller.
func perch_position() -> Vector3:
	return perch + Vector3.UP * 0.05


func _detach(body_pos: Vector3) -> void:
	strand_anchor = target
	strand_tip = body_pos + Vector3(0, 1.4, 0)
	strand_vel = Vector3.ZERO
	strand_t = STRAND_TIME


func cancel() -> void:
	phase = Phase.IDLE
	f_zip = Vector3.ZERO
	has_perch = false


func _strand_step(dt: float) -> void:
	if strand_t <= 0.0:
		return
	strand_t -= dt
	strand_vel += Vector3(0, -G, 0) * dt
	strand_vel *= maxf(1.0 - STRAND_DRAG * dt, 0.0)
	strand_tip += strand_vel * dt
	strand_tip.y = maxf(strand_tip.y, 0.05)


func _process(delta: float) -> void:
	var hand := global_position + Vector3(0, 1.4, 0)
	match phase:
		Phase.SHOOT:
			_seg(_line, hand, tip)
			_mark(target, true)
		Phase.PULL:
			_seg(_line, hand, target)
			_mark(target, true)
		_:
			_line.visible = false
			# Idle: refresh the perch hint a few times a second.
			_hint_t -= delta
			if _hint_t <= 0.0 and _body_rid.is_valid():
				_hint_t = 1.0 / PERCH_HINT_HZ
				var cam := get_viewport().get_camera_3d()
				if cam:
					find_perch(cam, _body_rid)
			_mark(perch, has_perch)
	if dash_line_t > 0.0:
		dash_line_t -= delta
		_seg(_line, dash_from, dash_hit)
	if strand_t > 0.0:
		_seg(_strand, strand_anchor, strand_tip)
	else:
		_strand.visible = false


func _mark(pos: Vector3, on: bool) -> void:
	_reticle.visible = on
	if on:
		_reticle.global_position = pos


func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var n := d.length()
	mi.visible = n > 0.01
	if n <= 0.01:
		return
	var z := d / n
	var up := Vector3.UP if absf(z.y) < 0.99 else Vector3.FORWARD
	var bs := Basis.looking_at(-z, up)
	mi.global_transform = Transform3D(bs.x, bs.y, bs.z * n, (a + b) * 0.5)
