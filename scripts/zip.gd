extends Node3D
## Zip to point. Aim from the camera, shoot a line, pull the body along a straight controlled path,
## then hand off cleanly: vault over a ledge, hop onto a top face, or push off a wall.
## Only real geometry is a valid target; empty sky never is.

const G := 9.8
enum Phase { IDLE, SHOOT, PULL }

const RANGE := 45.0                     # m, longest zip
const MIN_DIST := 3.0                   # m, closer hits are ignored (already there)
const SHOOT_TIME := 0.08                # s, line travel to the target
const ZIP_SPEED := 26.0                 # m/s, pull speed along the path
const ARRIVE_DIST := 1.7                # m, arrival radius
const VAULT_FWD := 6.0                  # m/s, Space near arrival: forward
const VAULT_UP := 7.5                   # m/s, Space near arrival: up
const LEDGE_HOP := 3.0                  # m/s, small hop when arriving on a top face
const WALL_PUSH := 3.5                  # m/s, push off a wall so the body does not stick
const STRAND_TIME := 2.0                # s, released strand lifetime
const STRAND_DRAG := 0.4                # 1/s

var phase := Phase.IDLE
var target := Vector3.ZERO
var target_normal := Vector3.UP
var shoot_from := Vector3.ZERO
var shoot_t := 0.0
var tip := Vector3.ZERO
var f_zip := Vector3.ZERO               # N, pull force this tick (for the FBD)
var work := 0.0                         # J, work done by the pull
var impulse := Vector3.ZERO             # N s, total impulse from the pull
var start_pos := Vector3.ZERO
var start_speed := 0.0
var last_displacement := Vector3.ZERO
var last_dk := 0.0
var last_du := 0.0
var last_arrival := ""                  # "vault" | "ledge" | "wall"
var strand_t := 0.0
var strand_anchor := Vector3.ZERO
var strand_tip := Vector3.ZERO
var strand_vel := Vector3.ZERO

var _line: MeshInstance3D
var _strand: MeshInstance3D
var _reticle: MeshInstance3D
var _aim_ok := false


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 1.0, 1.0)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)
	box.material = m
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.4
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


## Aim from the camera. Center ray first, then a small forgiving cone. Empty sky returns false.
func aim(cam: Camera3D, body_rid: RID) -> bool:
	var space := get_world_3d().direct_space_state
	var origin := cam.global_position
	var b := cam.global_transform.basis
	var fwd := -b.z
	var offs := [Vector2.ZERO, Vector2(0.05, 0), Vector2(-0.05, 0), Vector2(0, 0.05), Vector2(0, -0.05)]
	for off in offs:
		var dir: Vector3 = (fwd + b.x * off.x + b.y * off.y).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
		q.exclude = [body_rid]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var p: Vector3 = hit["position"]
		if origin.distance_to(p) < MIN_DIST:
			continue
		target = p
		target_normal = hit["normal"]
		_aim_ok = true
		return true
	_aim_ok = false
	return false


## Begin a zip to the current aim point. Returns false when there is no valid surface.
func start(cam: Camera3D, body_rid: RID, body_pos: Vector3, body_vel: Vector3) -> bool:
	if not aim(cam, body_rid):
		return false
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


## Advance the zip. Returns "pull", "arrived" or "idle". On "pull" the body velocity is set.
func step(dt: float, body: CharacterBody3D, mass: float) -> String:
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
		return "arrived"
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


## Finish the zip: vault with Space, hop onto a ledge top, or push off a wall. Returns velocity.
func arrive(body_vel: Vector3, cam_fwd: Vector3, vault: bool, mass: float) -> Vector3:
	var v := body_vel
	last_displacement = global_position - start_pos
	last_dk = 0.5 * mass * (v.length_squared() - start_speed * start_speed)
	last_du = mass * G * last_displacement.y
	work = last_dk + last_du  # Ch. 6: W_web = dK + dU_g, exact at the arrival point
	if vault:
		v = cam_fwd * VAULT_FWD + Vector3.UP * VAULT_UP
		last_arrival = "vault"
	elif target_normal.y > 0.6:
		v = Vector3(0, maxf(v.y, LEDGE_HOP), 0)
		last_arrival = "ledge"
	else:
		v = target_normal * WALL_PUSH + Vector3.UP * 1.5
		last_arrival = "wall"
	strand_anchor = target
	strand_tip = global_position + Vector3(0, 1.4, 0)
	strand_vel = Vector3.ZERO
	strand_t = STRAND_TIME
	phase = Phase.IDLE
	f_zip = Vector3.ZERO
	return v


func cancel() -> void:
	phase = Phase.IDLE
	f_zip = Vector3.ZERO


func aim_visible() -> bool:
	return _aim_ok


func _strand_step(dt: float) -> void:
	if strand_t <= 0.0:
		return
	strand_t -= dt
	strand_vel += Vector3(0, -G, 0) * dt
	strand_vel *= maxf(1.0 - STRAND_DRAG * dt, 0.0)
	strand_tip += strand_vel * dt
	strand_tip.y = maxf(strand_tip.y, 0.05)


func _process(_delta: float) -> void:
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
			_mark(target, _aim_ok)
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
