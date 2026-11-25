extends CharacterBody3D
## Physics movement controller.
## Step 1: idle, walk, run, jump, fall, dev fly. Step 2: charged super jump, dive and fast dive,
## and a Landing state after heavy drops. Each step sums explicit forces, integrates velocity, then
## move_and_slide resolves contacts. Godot's solver owns the touchdown; this script only reads it.
## Child "Visual" is cosmetic only; its "Body" mesh is recolored per state.

enum State { IDLE, WALK, RUN, JUMP, FALL, FLY, CHARGE, SUPER, DIVE, FAST_DIVE, LAND, ZIP }
const STATE_NAMES := ["IDLE", "WALK", "RUN", "JUMP", "FALL", "DEV-FLY", "CHARGE", "SUPER JUMP", "DIVE", "FAST DIVE", "LAND", "ZIP"]
const STATE_COLORS := [
	Color(0.6, 0.6, 0.6), Color(0.2, 0.8, 0.3), Color(1.0, 0.55, 0.0),
	Color(0.2, 0.8, 1.0), Color(0.9, 0.2, 0.8), Color(1.0, 1.0, 1.0),
	Color(1.0, 0.9, 0.1), Color(0.6, 0.1, 1.0), Color(0.1, 0.3, 1.0),
	Color(1.0, 0.1, 0.1), Color(0.5, 0.3, 0.1), Color(0.0, 0.95, 0.85),
]

const MASS := 70.0           # kg
const G := 9.8               # m/s^2
const WALK_SPEED := 5.0      # m/s
const RUN_SPEED := 9.0       # m/s
const MU_GRIP := 6.5         # ground grip coefficient (game tuning). Caps traction.
const GRIP_ACCEL := MU_GRIP * G  # m/s^2, max ground accel or brake
const AIR_ACCEL := 2.0       # m/s^2, air steering outside a dive
const JUMP_HEIGHT := 1.2     # m, tap jump apex
const SUPER_HEIGHT := 10.0   # m, full-charge apex
const SUPER_HORIZ := 8.0     # m/s, horizontal launch speed when WASD held at release
const CHARGE_TIME := 1.0     # s, hold time for full charge
const TAP_TIME := 0.2        # s, a shorter hold is a normal jump
const CONTACT_T := 0.05      # s, push-off contact time; launch force = J / CONTACT_T
const DRAG_K := 0.3          # kg/m, normal air drag: F_d = k |v| v
const DRAG_K_FAST := 0.15    # kg/m, fast dive: smaller effective cross-section
const DIVE_DROP := 2.0       # m below the air peak before a dive begins
const DIVE_STEER := 3.0      # m/s^2, normal dive steering
const DIVE_STEER_FAST := 1.0 # m/s^2, fast dive steering
const LAND_DROP := 3.0       # m, a fall this far below the air peak counts as a heavy landing
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
var f_zip := Vector3.ZERO       # N, zip pull force (F3 FBD)
var net := Vector3.ZERO
var accel := Vector3.ZERO
var last_impulse := Vector3.ZERO
var last_event := "none"
var peak_fn := 0.0           # N, largest normal force from the last launch or touchdown
var impact_force := 0.0      # N, normal force of the solver's stop on the touchdown frame: m * dv / dt
var charging := false
var charge_t := 0.0          # s, how long jump is held on the ground
var launch_super := false    # true while rising from a super jump
var landing := false         # true from a heavy touchdown until the player gives input
var diving := false
var fast := false
var air_peak := 0.0          # m, highest point since leaving the ground
var drag_loss := 0.0         # J, energy removed by air drag since takeoff

var _shown := -1

@onready var visual: Node3D = $Visual
@onready var web_l = $WebLeft
@onready var web_r = $WebRight
@onready var zip_node = $Zip
@onready var cam_ref: Camera3D = $Pivot/Pitch/Arm/Camera
@onready var state_label: Label3D = $StateLabel


func _physics_process(dt: float) -> void:
	if OS.is_debug_build() and Input.is_action_just_pressed("debug_fly"):
		fly = not fly
		velocity = Vector3.ZERO
		charging = false
		launch_super = false
		landing = false
		drag_loss = 0.0
	wish = _camera_relative_wish()
	sprint = Input.is_action_pressed("sprint")
	if Input.is_action_just_pressed("zip") and not fly and zip_node.phase == zip_node.Phase.IDLE:
		_zip_start()
	if zip_node.phase != zip_node.Phase.IDLE:
		_zip_tick(dt)
	elif fly:
		_fly(dt)
	else:
		_walk(dt)
	_set_state(_refine_state(state_for(fly, grounded, velocity.y, wish.length_squared() > 0.01, sprint)))
	_turn_visual(dt)


func _walk(dt: float) -> void:
	var was_grounded := grounded
	grounded = is_on_floor()
	if grounded:
		air_peak = global_position.y
	else:
		air_peak = maxf(air_peak, global_position.y)  # highest point of the arc, for the dive threshold

	# Landing is opposite of idle: any movement or jump input ends it.
	if wish.length_squared() > 0.01 or Input.is_action_just_pressed("jump"):
		landing = false

	_web_input()
	var want := wish * (RUN_SPEED if sprint else WALK_SPEED)
	diving = not grounded and velocity.y < 0.0 and air_peak - global_position.y >= DIVE_DROP
	fast = diving and Input.is_action_pressed("fast_dive")

	# Jump: a press starts a charge on the ground. The release picks tap jump or super jump.
	if grounded and Input.is_action_just_pressed("jump"):
		charging = true
		charge_t = 0.0
	if charging:
		if grounded:
			charge_t += dt
		else:
			charging = false  # walked off the edge mid-charge: no launch
	if charging and Input.is_action_just_released("jump"):
		_launch()

	if charging:
		want = Vector3.ZERO  # crouch-charge: brake horizontally, WASD only sets the launch direction
	f_g = Vector3(0, -MASS * G, 0)
	if grounded:
		f_n = Vector3(0, MASS * G, 0)
		f_app = traction(Vector3(velocity.x, 0, velocity.z), want, dt)
	else:
		f_n = Vector3.ZERO
		var steer := DIVE_STEER_FAST if fast else (DIVE_STEER if diving else AIR_ACCEL)
		f_app = Vector3.ZERO if _web_on() else wish * steer * MASS  # the rope owns the motion while swinging
	f_d = drag(velocity, DRAG_K_FAST if fast else DRAG_K)
	net = f_g + f_n + f_app + f_d
	accel = net / MASS
	velocity += accel * dt
	velocity += _web_step(dt)
	if not grounded:
		drag_loss += -f_d.dot(velocity) * dt
	var pre_vy := velocity.y
	move_and_slide()  # the solver stops the body on the floor; nothing below writes velocity.y
	var now_grounded := is_on_floor()
	web_l.project(self, now_grounded)  # fixed-length rope: back onto the arc after the solver moved the body
	web_r.project(self, now_grounded)
	if was_grounded and not now_grounded:
		air_peak = global_position.y  # takeoff
	if now_grounded and not was_grounded:
		impact_force = 0.0
		if pre_vy < -0.5:
			impact_force = MASS * absf(velocity.y - pre_vy) / dt  # FBD spike: the solver's stop, shown not integrated
			_touchdown(-pre_vy, air_peak - global_position.y)
	grounded = now_grounded
	if not grounded:
		landing = false


func _web_on() -> bool:
	return web_l.phase != web_l.Phase.IDLE or web_r.phase != web_r.Phase.IDLE


func _web_input() -> void:
	var fwd := _flat_forward()
	if Input.is_action_just_pressed("web_left") and web_l.phase == web_l.Phase.IDLE:
		web_l.fire(cam_ref, get_rid())
	if Input.is_action_just_pressed("web_right") and web_r.phase == web_r.Phase.IDLE:
		web_r.fire(cam_ref, get_rid())
	if Input.is_action_just_released("web_left"):
		_launch_web(web_l, fwd)
	if Input.is_action_just_released("web_right"):
		_launch_web(web_r, fwd)


func _launch_web(w, fwd: Vector3) -> void:
	var kick: Vector3 = w.release(fwd, velocity.length())
	if kick != Vector3.ZERO:
		velocity += kick


func _web_step(dt: float) -> Vector3:
	var fwd := _flat_forward()  # swing drive uses camera yaw only; pitch must not push the body into the floor
	var dv: Vector3 = web_l.step(dt, MASS, velocity, fwd, wish, grounded)
	dv += web_r.step(dt, MASS, velocity, fwd, wish, grounded)
	return dv


func _flat_forward() -> Vector3:
	var f := -cam_ref.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


func _zip_start() -> void:
	# One traversal at a time: drop any web so the rope cannot fight the pull.
	web_l.release(_flat_forward(), velocity.length())
	web_r.release(_flat_forward(), velocity.length())
	charging = false
	if zip_node.start(cam_ref, get_rid(), global_position, velocity):
		last_event = "Zip fire"


func _zip_tick(dt: float) -> void:
	var r: String = zip_node.step(dt, self, MASS)
	f_g = Vector3(0, -MASS * G, 0)
	f_d = drag(velocity)
	f_n = Vector3.ZERO
	f_zip = zip_node.f_zip
	net = f_g + f_d + f_zip
	accel = net / MASS
	if r == "arrived":
		velocity = zip_node.arrive(velocity, _flat_forward(), Input.is_action_pressed("jump"), MASS)
		last_impulse = MASS * velocity
		last_event = "Zip " + zip_node.last_arrival
		f_zip = Vector3.ZERO
		net = f_g + f_d
		accel = net / MASS
		grounded = false
	move_and_slide()
	grounded = is_on_floor()
	if not grounded:
		landing = false


func _launch() -> void:
	charging = false
	landing = false
	var tap := charge_t < TAP_TIME
	var charge := 0.0 if tap else clampf(charge_t / CHARGE_TIME, 0.0, 1.0)
	var old_v := velocity
	velocity.y = speed_for_height(super_height(charge))
	if not tap and wish.length_squared() > 0.01:
		velocity.x = wish.x * SUPER_HORIZ
		velocity.z = wish.z * SUPER_HORIZ
	grounded = false  # skip this frame's ground traction so the launch velocity stays intact
	launch_super = not tap
	last_impulse = MASS * (velocity - old_v)  # Ch.6: J = m dv
	peak_fn = MASS * G + last_impulse.length() / CONTACT_T
	last_event = "Jump" if tap else "Super jump"
	air_peak = global_position.y
	drag_loss = 0.0


func _touchdown(impact: float, drop: float) -> void:
	last_impulse = Vector3(0, MASS * impact, 0)  # Ch.6: J = m dv, the ground removes this momentum
	peak_fn = MASS * G + impact_force
	launch_super = false
	landing = drop >= LAND_DROP
	last_event = "Landing"


func _refine_state(s: State) -> State:
	if zip_node.phase != zip_node.Phase.IDLE:
		return State.ZIP
	if grounded and landing:
		return State.LAND
	if charging:
		return State.CHARGE
	if not grounded and (s == State.JUMP or s == State.FALL):
		if diving:
			return State.FAST_DIVE if fast else State.DIVE
		if launch_super and velocity.y > 0.0:
			return State.SUPER
	return s


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
	var label: String = STATE_NAMES[s]
	if s == State.CHARGE:
		var n := roundi(clampf(charge_t / CHARGE_TIME, 0.0, 1.0) * 10.0)
		var bar := ""
		for i in 10:
			bar += "#" if i < n else "-"
		label += "  [" + bar + "]"
	state = s
	state_label.text = label
	if s == _shown:
		return
	_shown = s
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


static func drag(v: Vector3, k: float = DRAG_K) -> Vector3:
	return -k * v.length() * v


static func speed_for_height(h: float) -> float:
	return sqrt(2.0 * G * h)


static func jump_speed() -> float:
	return speed_for_height(JUMP_HEIGHT)


static func super_height(charge: float) -> float:
	return lerpf(JUMP_HEIGHT, SUPER_HEIGHT, charge)


static func state_for(fly_on: bool, on_floor: bool, vy: float, moving: bool, run: bool) -> State:
	if fly_on:
		return State.FLY
	if not on_floor:
		return State.JUMP if vy > 0.0 else State.FALL
	if not moving:
		return State.IDLE
	return State.RUN if run else State.WALK
