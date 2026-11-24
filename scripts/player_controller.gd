extends CharacterBody3D
## Physics movement controller (Step 1: idle, walk, run, jump, fall, dev fly).
## Each step sums explicit forces, integrates velocity, then move_and_slide resolves contacts.
## Child "Visual" is cosmetic only. Its "Body" mesh is recolored per state. Swap the rigged model in later.

enum State { IDLE, WALK, RUN, JUMP, FALL, FLY }
const STATE_NAMES := ["IDLE", "WALK", "RUN", "JUMP", "FALL/DIVE", "DEV-FLY"]
const STATE_COLORS := [
	Color(0.6, 0.6, 0.6), Color(0.2, 0.8, 0.3), Color(1.0, 0.55, 0.0),
	Color(0.2, 0.8, 1.0), Color(0.9, 0.2, 0.8), Color(1.0, 1.0, 1.0),
]

const MASS := 70.0           # kg
const G := 9.8               # m/s^2
const WALK_SPEED := 5.0      # m/s
const RUN_SPEED := 9.0       # m/s
const MU_GRIP := 6.5         # ground grip coefficient (game tuning, not rubber-on-concrete). Caps traction.
const GRIP_ACCEL := MU_GRIP * G  # m/s^2, max ground accel or brake; 5 m/s stop ~0.08 s, 9 m/s ~0.14 s
const AIR_ACCEL := 2.0       # m/s^2, air steering force cap
const JUMP_HEIGHT := 1.2     # m
const DRAG_K := 0.3          # kg/m, F_d = k |v| v  (0.5 * rho 1.2 * Cd 1.0 * A 0.5)
const TURN_RATE := 12.0      # 1/s, visual turn smoothing
const FLY_SPEED := 14.0      # m/s, dev noclip only

var state := State.IDLE
var grounded := false
var sprint := false
var fly := false
var wish := Vector3.ZERO
var f_g := Vector3.ZERO
var f_n := Vector3.ZERO
var f_app := Vector3.ZERO
var f_d := Vector3.ZERO
var net := Vector3.ZERO
var accel := Vector3.ZERO
var last_impulse := Vector3.ZERO

@onready var visual: Node3D = $Visual
@onready var state_label: Label3D = $StateLabel


func _physics_process(dt: float) -> void:
	if OS.is_debug_build() and Input.is_action_just_pressed("debug_fly"):
		fly = not fly
		velocity = Vector3.ZERO
	wish = _camera_relative_wish()
	sprint = Input.is_action_pressed("sprint")
	if fly:
		_fly(dt)
	else:
		_walk(dt)
	_set_state(state_for(fly, grounded, velocity.y, wish.length_squared() > 0.01, sprint))
	_turn_visual(dt)


func _walk(dt: float) -> void:
	var want := wish * (RUN_SPEED if sprint else WALK_SPEED)
	grounded = is_on_floor()
	f_g = Vector3(0, -MASS * G, 0)
	f_n = Vector3(0, MASS * G, 0) if grounded else Vector3.ZERO
	# Grounded: F_app is ground traction (friction). Airborne: F_app is weak steering only, momentum is kept.
	f_app = traction(Vector3(velocity.x, 0, velocity.z), want, dt) if grounded else wish * AIR_ACCEL * MASS
	f_d = drag(velocity)
	if grounded and Input.is_action_just_pressed("jump"):
		var dv := jump_speed()
		velocity.y = dv
		last_impulse = Vector3(0, MASS * dv, 0)  # Ch.6: J = m dv
	net = f_g + f_n + f_app + f_d
	accel = net / MASS
	velocity += accel * dt
	move_and_slide()
	grounded = is_on_floor()
	if grounded and velocity.y < 0.0:
		velocity.y = 0.0


func _fly(dt: float) -> void:
	var up := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("fast_dive"))
	var dir := (wish + Vector3(0, up, 0)).limit_length(1.0)
	velocity = dir * FLY_SPEED
	# Dev noclip moves the body directly and skips collision on purpose.
	global_position += velocity * dt
	f_g = Vector3.ZERO
	f_n = Vector3.ZERO
	f_app = Vector3.ZERO
	f_d = Vector3.ZERO
	net = Vector3.ZERO
	accel = Vector3.ZERO
	grounded = false


func _turn_visual(dt: float) -> void:
	var h := Vector3(velocity.x, 0, velocity.z)
	if h.length() < 0.3:
		return
	var target := atan2(h.x, h.z)  # Visual local +Z faces the direction of travel
	visual.rotation.y = lerp_angle(visual.rotation.y, target, clampf(TURN_RATE * dt, 0.0, 1.0))


func _set_state(s: State) -> void:
	if s == state and state_label.text == STATE_NAMES[s]:
		return
	state = s
	state_label.text = STATE_NAMES[s]
	state_label.modulate = STATE_COLORS[s]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STATE_COLORS[s]
	(visual.get_node("Body") as MeshInstance3D).material_override = mat


func _camera_relative_wish() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var b := cam.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	var right := b.x
	right.y = 0.0
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return (right.normalized() * inp.x - fwd.normalized() * inp.y).limit_length(1.0)


static func traction(h_vel: Vector3, want: Vector3, dt: float) -> Vector3:
	# Limit the velocity change per step to GRIP_ACCEL*dt. Friction force F = m*dv/dt, capped at mu*m*g.
	# Stops at a fixed rate with no exponential tail (the old tau-based form slid ~0.85 s).
	var dv := (want - h_vel).limit_length(GRIP_ACCEL * dt)
	return dv * MASS / dt


static func drag(v: Vector3) -> Vector3:
	return -DRAG_K * v.length() * v


static func jump_speed() -> float:
	return sqrt(2.0 * G * JUMP_HEIGHT)


static func state_for(fly_on: bool, on_floor: bool, vy: float, moving: bool, run: bool) -> State:
	if fly_on:
		return State.FLY
	if not on_floor:
		return State.JUMP if vy > 0.0 else State.FALL
	if not moving:
		return State.IDLE
	return State.RUN if run else State.WALK
