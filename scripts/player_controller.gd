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
const WALL_JUMP_TIME := 0.5   # s, how long a wall jump keeps the WALL JUMP state
const WALL_EDGE_TIME := 0.3   # s, edge transition window (climb over / step down)
const WALL_CLIMB_TIME := 0.3  # s, smooth climb from the wall face onto the roof
const WALL_WRAP_TIME := 0.15  # s, smooth slide around an outer corner onto the next face
const WALL_REATTACH_CD := 0.12  # s, no re-grabbing the wall just jumped off
const WALL_TURN_RATE := 14.0  # 1/s, visual turn while on a wall (smooth around corners)
const WALL_ATTACH_SPEED := 3.0  # m/s, grounded attach needs at least this much horizontal speed
const FLY_SPEED := 14.0      # m/s, dev noclip only
const ANIM_FADE := 0.18      # s, crossfade between the grounded clips (idle/walk/run)
const ANIM_SNAP := 0.10      # s, faster blend into the held jump / landing poses
const SWING_JUMP_LOOP_START := 0.4  # s, swing_jump = 0.2 s launch pose + 0.2 s blend, then loops from here to the end
const ANIM_RATE := 0.9       # clip seconds per second at walk speed; scaled by actual ground speed
const LEAN_PITCH := 35.0     # deg, biggest torso pitch toward the web anchor
const LEAN_BANK := 25.0      # deg, biggest roll into the swing arc
const LEAN_IN := 6.0         # 1/s, blend into the web lean
const LEAN_OUT := 4.0        # 1/s, blend back upright
const LEAN_PIVOT := 0.95     # m, the body leans around the hips, not the feet
const WALL_FACE_TIME := 0.18 # s, blend between the upright body and the wall frame
const WALL_HUG := 0.20       # m, clearance kept between the body and the face it is on
const WALL_CRAWL_PIVOT := 0.75  # m, the crawl pivots around the hips; the run around the feet

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
var swing_launch := false     # true from a swing launch until touchdown: SWING JUMP state
var wall_jump_t := 0.0       # s, WALL JUMP window after leaving a wall
var wall_cd := 0.0           # s, re-attach grace after a wall jump
var wall_cd_normal := Vector3.ZERO  # normal of the face that was jumped off
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
var lean_pitch := 0.0        # rad, cosmetic torso pitch toward the web (0 = upright)
var lean_roll := 0.0         # rad, cosmetic bank into the swing arc
var heading := 0.0           # rad, Visual yaw: local +Z faces the way the body is pointed
var wall_fwd := Vector3.FORWARD  # unit, last direction of travel along the face
var wall_pivot := 0.0        # m, body-space height the wall frame turns around
var wall_hug := 0.0          # m, how far the model is pulled toward the face

var _shown := -1
var _shown_webs := 0   # web count the current clip was picked for (1 vs 2 web variants)
var _landing_crack: MeshInstance3D
var _crack_age := -1.0
var _crack_released := false
const CRACK_LIFE := 1.6

@onready var visual: Node3D = $Visual
@onready var model: Node3D = visual.get_node_or_null("Model")  # null if the model is swapped
@onready var anim: AnimationPlayer = visual.get_node_or_null("Model/Rig/AnimationPlayer")  # null if the model is swapped
@onready var web_l = $WebLeft
@onready var web_r = $WebRight
@onready var zip_node = $Zip
@onready var wall_node = $Wall
@onready var cam_ref: Camera3D = $Pivot/Pitch/Arm/Camera
@onready var state_label: Label3D = $StateLabel


func _ready() -> void:
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
		# The first play of this external clip makes AnimationPlayer build its track cache. Do that
		# before the first frame, rather than during the player's first swing jump.
		_prewarm_animation("moves/swing_jump")


func _prewarm_animation(path: String) -> void:
	if not anim.has_animation(path):
		return
	anim.play(path, 0.0)
	anim.seek(0.0, true)
	anim.stop()



## Godot only loops a whole clip, so swing_jump (launch pose + loop) is not set to loop: when it
## runs out while still swinging-jumping, restart it past the launch pose.
func _on_anim_finished(clip: StringName) -> void:
	if state == State.SWING_JUMP and String(clip).ends_with("swing_jump"):
		anim.play(clip, 0.0)
		anim.seek(SWING_JUMP_LOOP_START, true)


func _physics_process(dt: float) -> void:
	if OS.is_debug_build() and Input.is_action_just_pressed("debug_fly"):
		fly = not fly
		velocity = Vector3.ZERO
		charging = false
		holding = false
		launch_super = false
		swing_launch = false
		landing = false
		drag_loss = 0.0
	wish = _camera_relative_wish()
	sprint = Input.is_action_pressed("sprint")
	f_wall = Vector3.ZERO
	f_grip = Vector3.ZERO
	wall_jump_t = maxf(wall_jump_t - dt, 0.0)
	wall_cd = maxf(wall_cd - dt, 0.0)
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
	_web_lean(dt)
	_update_anim(dt)
	_update_landing_crack(dt)


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
	return _web_count() > 0


## Live webs: 1 or 2. Picks the one-web or two-web variant of the swing clips.
func _web_count() -> int:
	var n := 0
	if web_l.phase != web_l.Phase.IDLE:
		n += 1
	if web_r.phase != web_r.Phase.IDLE:
		n += 1
	return n


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
			swing_launch = true  # released on the up-swing: a swing launch


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
	if wall_cd > 0.0 and wall_node.normal.dot(wall_cd_normal) > 0.7:
		return  # just jumped off this face: let the launch clear it first
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
		wall_cd = WALL_REATTACH_CD  # grace: launch clear of this face before it can grab again
		wall_cd_normal = wall_node.normal
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
			heading = atan2(zip_node.perch_outward.x, zip_node.perch_outward.z)  # face out over the drop
			visual.transform = Transform3D(Basis(Vector3.UP, heading), Vector3.ZERO)  # scripted arrival: snap
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
	swing_launch = true
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
	swing_launch = false
	landing = drop >= LAND_DROP
	if landing:
		_spawn_landing_crack()
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
	if not grounded and swing_launch and not diving:  # a dive keeps its own state
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
	var on: bool = wall_node.active()
	var h := Vector3(velocity.x, 0, velocity.z)
	if on:
		# Where the body points once it lets go: into the face it is on, whatever the speed.
		heading = atan2(-wall_node.normal.x, -wall_node.normal.z)
	elif h.length() >= 0.3:
		heading = lerp_angle(heading, atan2(h.x, h.z), clampf(TURN_RATE * dt, 0.0, 1.0))
	var want := Basis(Vector3.UP, heading)  # Visual local +Z faces the direction of travel
	if on:
		want = _wall_frame()
	elif state == State.FLY:
		# Dev-fly glide: pitch the upright body onto its velocity.
		want = want * Basis(Vector3.RIGHT, _air_pitch())
	var k := clampf((WALL_TURN_RATE if on else TURN_RATE) * dt, 0.0, 1.0)
	# Pivot and hug ramp with the same k as the rotation, so grabbing or leaving a face is one move.
	wall_pivot = lerpf(wall_pivot, WALL_CRAWL_PIVOT if wall_node.phase == wall_node.Phase.CRAWL else 0.0, k)
	wall_hug = lerpf(wall_hug, wall_node.rest_gap - WALL_HUG if on else 0.0, k)
	var b := visual.basis.slerp(want, k)
	var pivot := Vector3(0.0, wall_pivot, 0.0)
	visual.transform = Transform3D(b, pivot - b * pivot - wall_node.normal * wall_hug)


## Head-leads-travel pitch for the dive and dev-fly states: the model's up axis is aimed at the
## velocity, so a dive points where he falls and a glide points where he flies. 0 when still.
func _air_pitch() -> float:
	var run := Vector3(velocity.x, 0.0, velocity.z).length()
	if run < 0.01 and absf(velocity.y) < 0.01:
		return 0.0
	return atan2(run, velocity.y)


## Body frame on the face, built from the live normal so a slanted or tilted face tilts the body
## with it. RUN stands on the face: the body's up is the normal, so its "down" is into the surface
## and the feet stay planted; the chest follows travel along the face. CRAWL clings chest-first:
## the body's +Z is the inward normal and its up runs along the face.
func _wall_frame() -> Basis:
	var n: Vector3 = wall_node.normal
	var hv: Vector3 = wall_node.wall_vel - n * wall_node.wall_vel.dot(n)
	if hv.length() > 0.5:
		wall_fwd = hv.normalized()
	var face: Vector3 = wall_fwd - n * wall_fwd.dot(n)
	if face.length_squared() < 0.01:
		face = Vector3.UP - n * n.y
	face = face.normalized()
	if wall_node.phase == wall_node.Phase.CRAWL:
		var along: Vector3 = Vector3.UP - n * n.y
		if along.length_squared() < 0.01:
			along = face
		along = along.normalized()
		return Basis(along.cross(-n), along, -n)
	return Basis(n.cross(face), n, face)


## Cosmetic only: lean the body along the live web, so a swing pitches toward the anchor and
## banks into the arc instead of standing upright. Physics never reads it.
func _web_lean(dt: float) -> void:
	if model == null:
		return
	var to := _web_aim()
	var on := to.length_squared() > 0.04
	var want_pitch := 0.0
	var want_roll := 0.0
	if on:
		to = to.normalized()
		var vb := visual.global_transform.basis  # yaw only: +Z is the direction of travel
		var fwd := to.dot(vb.z)
		var lat := to.dot(vb.x)
		want_pitch = clampf(atan2(to.y, maxf(fwd, 0.15)), -deg_to_rad(LEAN_PITCH), deg_to_rad(LEAN_PITCH))
		want_roll = -clampf(atan2(lat, maxf(absf(fwd), 0.15)), -deg_to_rad(LEAN_BANK), deg_to_rad(LEAN_BANK))
	var k := 1.0 - exp(-(LEAN_IN if on else LEAN_OUT) * dt)
	lean_pitch = lerpf(lean_pitch, want_pitch, k)
	lean_roll = lerpf(lean_roll, want_roll, k)
	if absf(lean_pitch) < 0.002 and absf(lean_roll) < 0.002:
		model.transform = Transform3D.IDENTITY  # exactly upright when no web is up
		return
	var b := Basis.from_euler(Vector3(lean_pitch, 0.0, lean_roll))
	var pivot := Vector3(0.0, LEAN_PIVOT, 0.0)
	model.transform = Transform3D(b, pivot - b * pivot)


## Body -> live web anchor (both hands averaged), or the zip target; zero when neither is up.
func _web_aim() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	if web_l.phase != web_l.Phase.IDLE:
		sum += web_l.anchor - global_position
		n += 1
	if web_r.phase != web_r.Phase.IDLE:
		sum += web_r.anchor - global_position
		n += 1
	if n > 0:
		return sum / float(n)
	if zip_node.phase != zip_node.Phase.IDLE:
		return zip_node.target - global_position
	return Vector3.ZERO


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
	var webs := _web_count()
	if s == _shown and webs == _shown_webs:
		return
	_shown = s
	_shown_webs = webs
	_play_ground_clip(s)
	state_label.modulate = STATE_COLORS[s]
	var body := visual.get_node_or_null("Body") as MeshInstance3D  # absent with a real model
	if body:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = STATE_COLORS[s]
		body.material_override = mat


## State -> clip. Swing states pick the one-web or two-web variant from the live web count.
## Unlisted states leave the last clip running through its crossfade. Clips live in the rig's
## "moves" library: the ground/air set from tools/normalize_rig.gd, the web set from
## tools/add_swing_clips.gd.
func _play_ground_clip(s: State) -> void:
	if anim == null:
		return
	var clip := ""
	match s:
		State.IDLE: clip = "idle"
		State.WALK: clip = "walk"
		State.RUN: clip = "run"
		State.JUMP: clip = "jump"
		State.FALL: clip = "fall"
		State.LAND: clip = "land"
		State.SWING_UP: clip = "swing_up_%d" % _web_count()
		State.SWING_DOWN: clip = "swing_down_%d" % _web_count()
		State.SWING_JUMP: clip = "swing_jump"
		State.ZIP: clip = "zip"
		State.CHARGE: clip = "charge"
		State.SUPER: clip = "super_jump"
		State.DIVE: clip = "dive"
		State.FAST_DIVE: clip = "fast_dive"
		State.FLY: clip = "dev_fly"
		State.WATCHING: clip = "watching"
		# WALL RUN has no clip of its own: it is the run stride, re-aimed at the face by the body frame.
		State.WALL_RUN: clip = "run"
		State.WALL_CRAWL: clip = "wall_crawl"
		State.WALL_JUMP: clip = "wall_jump"
		State.WALL_EDGE_UP: clip = "wall_edge_up"
		State.WALL_EDGE_DOWN: clip = "wall_edge_down"
		_:
			return
	if anim.has_animation("moves/" + clip):
		# Impact states snap; the ground trio keeps the slower blend.
		var snap: bool = s == State.JUMP or s == State.LAND or s == State.SWING_JUMP or s == State.WALL_JUMP
		var fade: float = ANIM_SNAP if snap else ANIM_FADE
		anim.play("moves/" + clip, fade)


## Playback follows real ground speed, so 5 m/s reads as a walk and 9 m/s as a run. On a face the
## same rule applies to speed ALONG the face: a crawl with no input holds its current pose exactly
## (speed_scale 0) and picks the motion back up when the body starts moving again.
func _update_anim(_dt: float) -> void:
	if anim == null:
		return
	if state == State.FALL:
		# Faster descent advances the fall pose without changing physics or the clip's loop.
		anim.speed_scale = clampf(0.8 + absf(velocity.y) / 18.0, 0.8, 1.4)
	elif state == State.WALL_CRAWL:
		var v: float = wall_node.wall_vel.length()
		anim.speed_scale = 0.0 if v < 0.2 else clampf(ANIM_RATE * v / WALK_SPEED, 0.6, 1.4)
	elif state == State.WALL_RUN:
		anim.speed_scale = clampf(ANIM_RATE * wall_node.wall_vel.length() / WALK_SPEED, 0.8, 1.4)
	elif state == State.SWING_UP or state == State.SWING_DOWN or state == State.SWING_JUMP or state == State.ZIP \
			or state == State.WALL_JUMP or state == State.WALL_EDGE_UP or state == State.WALL_EDGE_DOWN \
			or state == State.CHARGE or state == State.SUPER or state == State.DIVE or state == State.FAST_DIVE \
			or state == State.FLY or state == State.WATCHING:
		# Web clips, the wall one-shots and the held air/perch poses: physics and the state window set timing.
		anim.speed_scale = 1.0
	else:
		anim.speed_scale = clampf(ANIM_RATE * Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 0.8, 1.4)


func _spawn_landing_crack() -> void:
	_crack_age = 0.0
	_crack_released = false
	if is_instance_valid(_landing_crack):
		_landing_crack.queue_free()
		_landing_crack = null
	var from := global_position + Vector3.UP * 0.35
	var to := global_position + Vector3.DOWN * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal.normalized()
	var tangent := normal.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.01:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	# Eight tapered radial fractures with short branches, all slightly above the actual surface.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var d := tangent * cos(angle) + bitangent * sin(angle)
		var side := bitangent * cos(angle) - tangent * sin(angle)
		var start := point + normal * 0.006 + d * 0.03
		var finish := point + normal * 0.006 + d * (0.28 + 0.08 * sin(float(i) * 2.1))
		var width := 0.012
		var base := verts.size()
		verts.append_array([start - side * width, start + side * width, finish + side * width * 0.25, finish - side * width * 0.25])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		# One small branch off the middle of each fracture.
		var mid := start.lerp(finish, 0.55)
		var branch := (d * 0.65 + side * (1.0 if i % 2 == 0 else -1.0)).normalized()
		var b_end := mid + branch * 0.09
		var bb := verts.size()
		verts.append_array([mid - side * width * 0.65, mid + side * width * 0.65, b_end + side * width * 0.15, b_end - side * width * 0.15])
		indices.append_array([bb, bb + 1, bb + 2, bb, bb + 2, bb + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_landing_crack = MeshInstance3D.new()
	_landing_crack.name = "LandingCrack"
	_landing_crack.mesh = mesh
	# Vertices are already in world coordinates from the ray hit; no second transform or decal projection.
	_landing_crack.global_transform = Transform3D.IDENTITY
	# Sample the rendered surface under the contact point and darken it: no unrelated decal colour.
	var tint := Color(0.08, 0.06, 0.05, 0.86)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var px := cam.unproject_position(point)
		var image := get_viewport().get_texture().get_image()
		if image and Rect2(Vector2.ZERO, image.get_size()).has_point(px):
			var sampled := image.get_pixelv(px)
			tint = Color(sampled.r * 0.28, sampled.g * 0.24, sampled.b * 0.20, 0.86)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_landing_crack.material_override = material
	get_tree().root.add_child(_landing_crack)


func _update_landing_crack(dt: float) -> void:
	if _crack_age < 0.0 or not is_instance_valid(_landing_crack):
		return
	_crack_age += dt
	if state != State.LAND:
		_crack_released = true  # LAND ended; let the impact mark fade instead of vanishing on the state edge.
	var fade_start := 0.35 if not _crack_released else 0.0
	var fade := 1.0 - clampf(maxf(_crack_age - fade_start, 0.0) / (CRACK_LIFE - fade_start), 0.0, 1.0)
	var mat := _landing_crack.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.86 * fade
	if _crack_age >= CRACK_LIFE:
		_landing_crack.queue_free()
		_landing_crack = null
		_crack_age = -1.0


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
