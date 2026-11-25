extends Node3D
const Layers := preload("res://scripts/layers.gd")  # collision layer bits
## One web per hand. Fixed-length pendulum, solved in two places:
##  - step(): before integration, remove outward radial speed while taut and add tangential drive.
##  - project(): after move_and_slide, put the body back on the rope sphere, so the rope never
##    stretches or shrinks. The arc radius is exactly `length` metres.
## Anchors come from a fan biased high, forward and toward this hand's side, on real geometry only.

const G := 9.8
enum Phase { IDLE, SHOOT, ROPE }

const RANGE := 45.0                     # m, longest web shot
const SHOOT_TIME := 0.1                 # s, line travel from hand to anchor
const MIN_ANCHOR_Y := 3.5               # m, lower hits are ground, not an anchor
const MIN_ANCHOR_RISE := 2.5            # m, anchor must be at least this far above the player
const FAN_YAW := [12.0, 24.0, 36.0, 48.0, 60.0]   # deg, toward this hand's side
const FAN_PITCH := [15.0, 30.0, 45.0, 60.0]       # deg above horizontal
const PREF_DIST := 12.0                 # m, ideal rope length
const MAX_REACH := 30.0                 # m, longer hits lose hard
const ATTACH_FWD := 7.0                 # m/s, forward momentum the web hands you when it bites
const REEL_RATE := 12.0                 # m/s, rope shortens right after the web bites: the yank that lifts a ground shot
const REEL_TIME := 0.35                 # s, how long the attach reel lasts
const SWING_ASSIST := 8.0               # m/s^2, tangential push toward camera forward
const SWING_EXTRA_G := 2.5             # m/s^2, extra downward pull while swinging: heavier, less floaty
const PUMP := 5.0                       # m/s^2, tangential push from held WASD
const MAX_SWING := 26.0                 # m/s, assist stops above this speed
const CASE_A_FWD := 6.0                 # m/s, anchor ahead: strong forward boost
const CASE_A_UP := 6.0                 # m/s, strong upward boost
const CASE_B_FWD := 1.6                # m/s, anchor behind: subtle forward lift
const CASE_B_UP := 1.6                 # m/s, subtle upward lift
const RELEASE_REF_SPEED := 10.0        # m/s, at or below this the kick is full strength
const RELEASE_FALLOFF := 0.08          # kick scale lost per m/s above the reference
const RELEASE_MIN_SCALE := 0.4         # never scale the kick below 40%
const RELEASE_MAX_SPEED := 24.0        # m/s, total speed cap after the kick
const STRAND_FADE := 0.6                # s, alpha fade at the end of the strand life
const STRAND_TIME := 2.0                # s, falling strand lifetime after release
const STRAND_DRAG := 0.4                # 1/s

var phase := Phase.IDLE
var side := -1.0                        # -1 left, +1 right (set by the scene)
var anchor := Vector3.ZERO
var length := 0.0                       # m, fixed arc radius while swinging
var shoot_from := Vector3.ZERO
var shoot_t := 0.0
var reel_t := 0.0                       # s, attach reel time left
var tip := Vector3.ZERO
var toward := Vector3.ZERO              # unit vector from body to anchor
var last_tension := 0.0                 # N
var last_radius := 0.0                  # m
var last_vt := 0.0                      # m/s, tangential speed
var last_ac := 0.0                      # m/s^2
var last_case := ""                     # "A" or "B" from the last release
var strand_t := 0.0
var strand_anchor := Vector3.ZERO
var strand_tip := Vector3.ZERO
var strand_vel := Vector3.ZERO

var _line: MeshInstance3D
var _strand: MeshInstance3D
var _strand_mat: StandardMaterial3D
var _mark: MeshInstance3D


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.92, 0.95, 1.0)
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)
	box.material = m
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.92, 0.95, 1.0)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.05, 0.05, 1.0)
	sbox.material = sm
	_strand_mat = sm
	var ball := SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.28
	ball.material = m
	_line = _make(box)
	_strand = _make(sbox)  # own material so it can fade
	_mark = _make(ball)
	_line.visible = false
	_strand.visible = false
	_mark.visible = false


func _make(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true  # world space, so the line does not inherit the body's rotation
	add_child(mi)
	return mi


## Search this hand's fan for a building face. Higher and forward wins, far or low loses.
func fire(cam: Camera3D, body_rid: RID) -> bool:
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var origin := global_position
	var best := Vector3.ZERO
	var best_sc := -1e9
	for yd in FAN_YAW:
		for pd in FAN_PITCH:
			var yaw := deg_to_rad(yd) * side
			var pitch := deg_to_rad(pd)
			var h := fwd * cos(yaw) + right * sin(yaw)
			var dir := (h * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
			var q := Layers.ray(origin, origin + dir * RANGE)
			q.exclude = [body_rid]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				continue
			var p: Vector3 = hit["position"]
			if p.y < MIN_ANCHOR_Y or p.y < origin.y + MIN_ANCHOR_RISE:
				continue
			var off := p - origin
			var d := off.length()
			var fwd_reach := off.dot(fwd)
			if fwd_reach < 1.0:
				continue  # straight up or behind: no forward swing
			# Height dominates, forward reach adds, distance away from PREF_DIST costs.
			var sc := p.y * 1.0 + fwd_reach * 0.9 - absf(d - PREF_DIST) * 0.5
			var arc_bottom := p.y - d  # lowest point of the swing circle
			if arc_bottom < 1.5:
				sc -= (1.5 - arc_bottom) * 6.0  # an arc that dips under the floor cannot swing
			if d > MAX_REACH:
				sc -= (d - MAX_REACH) * 4.0
			if sc > best_sc:
				best_sc = sc
				best = p
	if best_sc == -1e9:
		return false
	anchor = best
	shoot_from = origin
	tip = origin
	shoot_t = 0.0
	phase = Phase.SHOOT
	return true


## Let go. Returns the launch velocity change (m/s).
func release(cam_fwd: Vector3, speed: float) -> Vector3:
	var kick := Vector3.ZERO
	if phase == Phase.ROPE:
		var ahead := (anchor - global_position).dot(cam_fwd) > 0.0
		last_case = "A" if ahead else "B"
		kick = scaled_kick(ahead, cam_fwd, speed)
		strand_anchor = anchor
		strand_tip = global_position + Vector3(0, 1.4, 0)
		strand_vel = Vector3.ZERO
		strand_t = STRAND_TIME
	phase = Phase.IDLE
	toward = Vector3.ZERO
	last_tension = 0.0
	length = 0.0
	return kick


static func kick_for(ahead: bool, fwd: Vector3) -> Vector3:
	if ahead:
		return fwd * CASE_A_FWD + Vector3.UP * CASE_A_UP
	return fwd * CASE_B_FWD + Vector3.UP * CASE_B_UP


## Release kick for the speed the body already carries: fast swings get a smaller kick,
## and total speed after the kick never exceeds RELEASE_MAX_SPEED.
static func scaled_kick(ahead: bool, fwd: Vector3, speed: float) -> Vector3:
	var k := kick_for(ahead, fwd)
	k *= clampf(1.0 - (speed - RELEASE_REF_SPEED) * RELEASE_FALLOFF, RELEASE_MIN_SCALE, 1.0)
	var budget := maxf(RELEASE_MAX_SPEED - speed, 0.0)
	if k.length() > budget:
		k = k.normalized() * budget
	return k


## Advance shot/rope/strand one tick. Returns the velocity change to add before move_and_slide.
func step(dt: float, mass: float, vel: Vector3, cam_fwd: Vector3, wish: Vector3, on_floor: bool) -> Vector3:
	if phase == Phase.SHOOT:
		shoot_t += dt
		var f := minf(shoot_t / SHOOT_TIME, 1.0)
		tip = shoot_from.lerp(anchor, f)
		if f >= 1.0:
			phase = Phase.ROPE
			length = global_position.distance_to(anchor)
			reel_t = REEL_TIME  # the yank: rope shortens briefly, the projection pulls the body up the arc
			return cam_fwd * ATTACH_FWD  # and it hands you forward speed, so the arc carries you through
		return Vector3.ZERO
	if phase != Phase.ROPE:
		return Vector3.ZERO
	var d := anchor - global_position
	var dist := d.length()
	if dist < 0.001:
		return Vector3.ZERO
	toward = d / dist
	if reel_t > 0.0:
		reel_t -= dt
		length = maxf(length - REEL_RATE * dt, 4.0)  # reel in for a moment, then hold a fixed swing length
	var radial := vel.dot(toward)           # + toward the anchor, - away from it
	var v_tan := vel - toward * radial
	last_radius = dist
	last_vt = v_tan.length()
	last_ac = last_vt * last_vt / dist
	var dv := Vector3.ZERO
	if dist >= length - 0.02:
		if radial < 0.0:
			dv += toward * -radial        # remove outward speed, keep the tangent motion
		last_tension = maxf(mass * (last_ac + G * toward.y), 0.0)
		if not on_floor:
			dv += Vector3.DOWN * SWING_EXTRA_G * dt  # heavier arc: the bottom of the swing pulls harder
		if not on_floor and vel.length() < MAX_SWING:
			var tf := cam_fwd - toward * cam_fwd.dot(toward)   # camera forward, in the swing plane
			if tf.length_squared() > 0.01:
				dv += tf.normalized() * SWING_ASSIST * dt
			var tw := wish - toward * wish.dot(toward)          # WASD, in the swing plane
			if tw.length_squared() > 0.01:
				dv += tw.normalized() * PUMP * dt
	else:
		last_tension = 0.0
	return dv


## After move_and_slide: put the body back on the rope sphere. Skipped on the floor, so the
## floor and the rope never fight over the position.
func project(body: CharacterBody3D, on_floor: bool) -> void:
	if phase != Phase.ROPE or length <= 0.001:
		return
	var d := anchor - body.global_position
	var dist := d.length()
	if dist <= length:
		return
	var dir: Vector3 = d / dist
	var target := anchor - dir * length
	if on_floor and target.y < body.global_position.y:
		return  # never push a grounded body into the floor; upward corrections still lift it
	body.global_position = target
	var outward: float = body.velocity.dot(-dir)
	if outward > 0.0:
		body.velocity += dir * outward


func tension_vec() -> Vector3:
	return toward * last_tension if phase == Phase.ROPE else Vector3.ZERO


func _strand_step(dt: float) -> void:
	if strand_t <= 0.0:
		return
	strand_t -= dt
	strand_vel += Vector3(0, -G, 0) * dt
	strand_vel *= maxf(1.0 - STRAND_DRAG * dt, 0.0)
	strand_tip += strand_vel * dt
	strand_tip.y = maxf(strand_tip.y, 0.05)
	_strand_mat.albedo_color.a = clampf(strand_t / STRAND_FADE, 0.0, 1.0)  # timed fade out


func _process(delta: float) -> void:
	_strand_step(delta)  # keeps falling after the web is gone
	var hand := global_position + Vector3(0, 1.4, 0)
	match phase:
		Phase.SHOOT:
			_seg(_line, hand, tip)
			_mark.global_position = anchor
			_mark.visible = true
		Phase.ROPE:
			_seg(_line, hand, anchor)
			_mark.global_position = anchor
			_mark.visible = true
		_:
			_line.visible = false
			_mark.visible = false
	if strand_t > 0.0:
		_seg(_strand, strand_anchor, strand_tip)
	else:
		_strand.visible = false


func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var n := d.length()
	mi.visible = n > 0.01
	if n <= 0.01:
		return
	var z := d / n  # unit direction a -> b; the box is 1 m long along its +Z
	var up := Vector3.UP if absf(z.y) < 0.99 else Vector3.FORWARD
	var bs := Basis.looking_at(-z, up)  # looking_at aims -Z, so pass -z to get +Z along the segment
	mi.global_transform = Transform3D(bs.x, bs.y, bs.z * n, (a + b) * 0.5)
