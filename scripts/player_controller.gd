extends CharacterBody3D
## Physics movement controller.
## Step 1: idle, walk, run, jump, fall, dev fly. Step 2: charged super jump, dive and fast dive,
## and a Landing state after heavy drops. Each step sums explicit forces, integrates velocity, then
## move_and_slide resolves contacts. Godot's solver owns the touchdown; this script only reads it.
## Child "Visual" is cosmetic only; its "Body" mesh is recolored per state.

enum State { IDLE, WALK, RUN, JUMP, FALL, FLY, CHARGE, SUPER, DIVE, FAST_DIVE, LAND, ZIP, WATCHING, SWING_UP, SWING_DOWN, SWING_JUMP, WALL_CRAWL, WALL_RUN, WALL_JUMP, WALL_EDGE_UP, WALL_EDGE_DOWN }
const STATE_NAMES := ["IDLE", "WALK", "RUN", "JUMP", "FALL", "DEV-FLY", "CHARGE", "SUPER JUMP", "DIVE", "FAST DIVE", "LAND", "ZIP", "WATCHING", "SWING UP", "SWING DOWN", "SWING JUMP", "WALL CRAWL", "WALL RUN", "WALL JUMP", "WALL EDGE UP", "WALL EDGE DOWN"]
const STATE_COLORS := [
	Color(0.6, 0.6, 0.6), Color(0.2, 0.8, 0.3), Color(1.0, 0.55, 0.0),
	Color(0.2, 0.8, 1.0), Color(0.9, 0.2, 0.8), Color(1.0, 1.0, 1.0),
	Color(1.0, 0.9, 0.1), Color(0.6, 0.1, 1.0), Color(0.1, 0.3, 1.0),
	Color(1.0, 0.1, 0.1), Color(0.5, 0.3, 0.1), Color(0.0, 0.95, 0.85), Color(0.55, 0.35, 0.95),
	Color(0.35, 0.8, 1.0), Color(0.1, 0.35, 0.9), Color(0.95, 1.0, 0.35),
	Color(0.75, 0.55, 1.0), Color(0.95, 0.35, 0.65), Color(1.0, 1.0, 0.75),
	Color(0.6, 0.95, 0.6), Color(0.55, 0.7, 0.85),
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
const SWING_VY := 1.5        # m/s, |velocity.y| above this splits the swing into up/down states
const SWING_JUMP_UP := 6.0   # m/s, upward kick of a jump taken out of a swing
const SWING_JUMP_FWD := 3.0  # m/s, forward kick of a swing jump
const SWING_LAUNCH_TIME := 0.8  # s, how long a swing launch keeps the SWING JUMP state
const WALL_JUMP_TIME := 0.5   # s, how long a wall jump keeps the WALL JUMP state
const WALL_EDGE_TIME := 0.3   # s, edge transition window (climb over / step down)
const WALL_CLIMB_TIME := 0.3  # s, smooth climb from the wall face onto the roof
const WALL_WRAP_TIME := 0.15  # s, smooth slide around an outer corner onto the next face
const WALL_ATTACH_SPEED := 3.0  # m/s, grounded attach needs at least this much horizontal speed
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
var f_wall := Vector3.ZERO      # N, wall normal force (F3 FBD)
var f_grip := Vector3.ZERO      # N, wall friction holding the body up (F3 FBD)
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
var watching := false        # perched on a rooftop edge, holding still until input
var holding := false         # jump held on the ground, before the charge delay elapses
var swing_launch_t := 0.0    # s, SWING JUMP window left after leaving an up-swing
var wall_jump_t := 0.0       # s, WALL JUMP window after leaving a wall
var edge_up_t := 0.0         # s, WALL EDGE UP window after climbing onto a roof
var edge_down_t := 0.0       # s, WALL EDGE DOWN window after stepping off a wall
var wrapping := false        # mid corner wrap: a timed interpolation, no physics
var wrap_from := Vector3.ZERO
var wrap_to := Vector3.ZERO
var wrap_t := 0.0
var climbing := false        # mid climb-over: a timed interpolation, no physics
var climb_from := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_t := 0.0
var diving := false
var fast := false
var air_peak := 0.0          # m, highest point since leaving the ground
var drag_loss := 0.0         # J, energy removed by air drag since takeoff

var _shown := -1

@onready var visual: Node3D = $Visual
@onready var web_l = $WebLeft
@onready var web_r = $WebRight
@onready var zip_node = $Zip
@onready var wall_node = $Wall
@onready var cam_ref: Camera3D = $Pivot/Pitch/Arm/Camera
@onready var state_label: Label3D = $StateLabel


func _physics_process(dt: float) -> void:
	if OS.is_debug_build() and Input.is_action_just_pressed("debug_fly"):
		fly = not fly
		velocity = Vector3.ZERO
		charging = false
		holding = false
		launch_super = false
		swing_launch_t = 0.0
		landing = false
		drag_loss = 0.0
	wish = _camera_relative_wish()
	sprint = Input.is_action_pressed("sprint")
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO
	wall_jump_t = maxf(wall_jump_t - dt, 0.0)
	edge_up_t = maxf(edge_up_t - dt, 0.0)
	edge_down_t = maxf(edge_down_t - dt, 0.0)
	if Input.is_action_just_pressed("zip") and not fly and zip_node.phase == zip_node.Phase.IDLE:
		if _zip_start():
			watching = false  # a real zip started, so leave the perch
	if climbing:
		_climb_tick(dt)
	elif watching:
		_watching(dt)
	elif zip_node.phase != zip_node.Phase.IDLE:
		_zip_tick(dt)
	elif wall_node.active():
		_wall_tick(dt)
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

	# Jump: a press starts a hold on the ground. Movement is untouched until the hold passes
	# TAP_TIME; only then does the crouch-charge engage and brake. Release picks tap or super.
	if grounded and Input.is_action_just_pressed("jump"):
		holding = true
		charge_t = 0.0
		charging = false
	if holding:
		if grounded:
			charge_t += dt
			if charge_t >= TAP_TIME:
				charging = true  # the crouch now owns movement
		else:
			holding = false  # walked off the edge mid-hold: no launch
			charging = false
	if holding and Input.is_action_just_released("jump"):
		holding = false
		_launch()

	# Swing jump: Space while a web holds you launches off the arc, with its own state.
	if Input.is_action_just_pressed("jump") and not grounded and _web_on():
		_swing_jump()
	swing_launch_t = maxf(swing_launch_t - dt, 0.0)

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
	_try_wall_attach()


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
		if velocity.y > 0.0:
			swing_launch_t = SWING_LAUNCH_TIME  # released on the up-swing: a swing launch


func _web_step(dt: float) -> Vector3:
	var fwd := _flat_forward()  # swing drive uses camera yaw only; pitch must not push the body into the floor
	var dv: Vector3 = web_l.step(dt, MASS, velocity, fwd, wish, grounded)
	dv += web_r.step(dt, MASS, velocity, fwd, wish, grounded)
	return dv


func _cam_right() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.RIGHT
	return cam.global_transform.basis.x


func _flat_forward() -> Vector3:
	var f := -cam_ref.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


## Attach to a vertical face when the body is moving into it.
func _try_wall_attach() -> void:
	if fly or watching or zip_node.phase != zip_node.Phase.IDLE or _web_on():
		return
	if not wall_node.probe(self, _cam_right()):
		return
	if wish.dot(-wall_node.normal) < 0.3:
		return  # not heading into the wall
	if not grounded or Vector3(velocity.x, 0, velocity.z).length() > WALL_ATTACH_SPEED:
		wall_node.attach(self, _cam_right(), sprint)
		last_event = "Wall attach"


## On the wall: crawl/run, wall jump, and the two edge handoffs.
func _wall_tick(dt: float) -> void:
	if wrapping:
		wrap_t += dt
		var wt := clampf(wrap_t / WALL_WRAP_TIME, 0.0, 1.0)
		global_position = wrap_from.lerp(wrap_to, smoothstep(0.0, 1.0, wt))
		velocity = Vector3.ZERO
		f_wall = Vector3.ZERO
		f_grip = Vector3.ZERO
		f_g = Vector3(0, -MASS * G, 0)
		f_d = Vector3.ZERO
		f_n = Vector3.ZERO
		f_app = Vector3.ZERO
		net = f_g
		accel = Vector3.ZERO
		if wt >= 1.0:
			wrapping = false
		return
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cr := _cam_right()
	var r: String = wall_node.step(dt, self, inp, MASS, Input.is_action_just_pressed("jump"), sprint, cr)
	f_g = Vector3(0, -MASS * G, 0)
	f_d = drag(velocity)
	f_n = Vector3.ZERO  # on a wall the normal force is N, drawn separately from F_N
	f_app = Vector3.ZERO
	f_wall = wall_node.f_wall
	f_grip = wall_node.f_grip
	net = f_g + f_d + f_n + f_app
	accel = net / MASS
	if r == "jump":
		last_impulse = MASS * velocity
		last_event = "Wall jump"
		wall_jump_t = WALL_JUMP_TIME
		grounded = false
	move_and_slide()
	grounded = is_on_floor()
	if not wall_node.active():
		if not grounded:
			landing = false
		return
	if grounded:
		wall_node.detach()  # ran down to the floor
		edge_down_t = WALL_EDGE_TIME
		last_event = "Wall edge down"
		return
	# Stay on the face: re-check contact, pull back onto it, or wrap around an outer corner.
	if not wall_node.stick(self):
		var next_face: Vector3 = wall_node.wrap(self, cr)
		if next_face == Vector3.INF:
			wall_node.detach()  # nothing within reach: fall away cleanly
			last_event = "Wall detach"
			if not grounded:
				landing = false
			return
		wrapping = true
		wrap_from = global_position
		wrap_to = next_face
		wrap_t = 0.0
		last_event = "Wall corner wrap"
		return
	var roof: Vector3 = wall_node.top_edge(self)
	if roof != Vector3.INF:
		_start_climb(wall_node.roof_stand(roof))
	if not grounded:
		landing = false


## Timed climb from the face onto the roof. Kinematic: no physics while it runs, so the future
## climb-over animation can drive the same window.
func _start_climb(to: Vector3) -> void:
	climbing = true
	climb_t = 0.0
	climb_from = global_position
	climb_to = to
	velocity = Vector3.ZERO
	wall_node.detach()
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO
	last_event = "Wall edge up"


func _climb_tick(dt: float) -> void:
	climb_t += dt
	var t := clampf(climb_t / WALL_CLIMB_TIME, 0.0, 1.0)
	global_position = climb_from.lerp(climb_to, smoothstep(0.0, 1.0, t)) + Vector3.UP * sin(t * PI) * 0.12
	velocity = Vector3.ZERO
	f_g = Vector3(0, -MASS * G, 0)
	f_d = Vector3.ZERO
	f_n = Vector3.ZERO
	f_app = Vector3.ZERO
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO
	net = f_g
	accel = Vector3.ZERO
	grounded = false
	if t >= 1.0:
		climbing = false
		global_position = climb_to
		grounded = true
		edge_up_t = WALL_EDGE_TIME


## Ctrl: perch if a corner hint is in view, else a web pull at a real face, else nothing at all.
## Returns true only when something actually started, so an empty-air press changes no state.
func _zip_start() -> bool:
	# One traversal at a time: drop any web so the rope cannot fight the pull.
	web_l.release(_flat_forward(), velocity.length())
	web_r.release(_flat_forward(), velocity.length())
	charging = false
	landing = false
	if zip_node.start_perch(cam_ref, get_rid(), global_position, velocity):
		last_event = "Zip to perch"
		return true
	if zip_node.start_surface_boost(cam_ref, get_rid(), global_position, velocity):
		last_event = "Web-zip boost"
		return true
	return false  # aimed at empty air: no lunge, no web, no state change


func _zip_tick(dt: float) -> void:
	var r: String = zip_node.step(dt, self, MASS, Input.is_action_pressed("jump"))
	f_g = Vector3(0, -MASS * G, 0)
	f_d = drag(velocity)
	f_n = Vector3.ZERO
	f_zip = zip_node.f_zip
	net = f_g + f_d + f_zip
	accel = net / MASS
	match r:
		"perched":
			global_position = zip_node.perch_position()
			velocity = Vector3.ZERO
			visual.rotation.y = atan2(zip_node.perch_outward.x, zip_node.perch_outward.z)  # face out over the drop
			watching = true
			grounded = true
			last_event = "Perched"
			last_impulse = Vector3.ZERO
			f_zip = Vector3.ZERO
			net = Vector3.ZERO
			accel = Vector3.ZERO
			return
		"vault":
			velocity = zip_node.arrive_vel
			last_impulse = MASS * velocity
			last_event = "Perch vault"
			grounded = false
	move_and_slide()
	grounded = is_on_floor()
	if not grounded:
		landing = false


## Perched: hold still on the edge. Any movement, jump, web or zip input ends it.
func _watching(dt: float) -> void:
	velocity = Vector3.ZERO
	f_g = Vector3(0, -MASS * G, 0)
	f_n = Vector3(0, MASS * G, 0)
	f_app = Vector3.ZERO
	f_d = Vector3.ZERO
	f_zip = Vector3.ZERO
	net = f_g + f_n
	accel = Vector3.ZERO
	grounded = true
	if Input.is_action_just_pressed("jump"):
		# Point launch off the perch: a clean forward/up hop, not a walk-off.
		velocity = _flat_forward() * 4.0 + Vector3.UP * jump_speed() * 1.15
		last_impulse = MASS * velocity
		last_event = "Point launch"
		watching = false
	elif wish.length_squared() > 0.01:
		watching = false
	elif Input.is_action_just_pressed("web_left") or Input.is_action_just_pressed("web_right"):
		watching = false
		_web_input()


func _swing_jump() -> void:
	var fwd := _flat_forward()
	web_l.release(fwd, velocity.length())
	web_r.release(fwd, velocity.length())
	var kick := Vector3.UP * SWING_JUMP_UP + fwd * SWING_JUMP_FWD
	velocity += kick
	swing_launch_t = SWING_LAUNCH_TIME
	last_impulse = MASS * kick
	last_event = "Swing jump"
	charging = false
	holding = false


func _launch() -> void:
	charging = false
	holding = false
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
	swing_launch_t = 0.0
	landing = drop >= LAND_DROP
	last_event = "Landing"


func _refine_state(s: State) -> State:
	if watching:
		return State.WATCHING
	if zip_node.phase != zip_node.Phase.IDLE:
		return State.ZIP
	if climbing or edge_up_t > 0.0:
		return State.WALL_EDGE_UP
	if edge_down_t > 0.0:
		return State.WALL_EDGE_DOWN
	if wall_node.active():
		return State.WALL_RUN if wall_node.phase == wall_node.Phase.RUN else State.WALL_CRAWL
	if wall_jump_t > 0.0 and not grounded and velocity.y > 0.0:
		return State.WALL_JUMP
	if not grounded and _web_on():
		# Swing sub-states for future up/down animations. Dead zone holds the last one: no flicker.
		if velocity.y > SWING_VY:
			return State.SWING_UP
		if velocity.y < -SWING_VY:
			return State.SWING_DOWN
		if state == State.SWING_UP or state == State.SWING_DOWN:
			return state
		return State.SWING_UP
	if not grounded and swing_launch_t > 0.0 and velocity.y > 0.0:
		return State.SWING_JUMP
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
