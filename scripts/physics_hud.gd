extends Node3D
## F3 physics overlay (Giancoli Ch. 1-8). Hidden at startup. Developer block only in debug builds.

const N_TO_M := 0.004  # display scale: arrow length in metres per newton
const VEC_NAMES := ["F_g", "F_N", "F_app", "F_d", "T", "F_zip"]
const VEC_COLORS := [Color.RED, Color.GREEN, Color.DEEP_SKY_BLUE, Color.YELLOW, Color.MAGENTA, Color.CYAN]
const CTRL := preload("res://scripts/player_controller.gd")

var DEV := OS.is_debug_build()
var _p: CharacterBody3D
var _text: Label
var _mi: MeshInstance3D
var _lines: ImmediateMesh
var _tags: Array[Label3D] = []
var _on := false


func _ready() -> void:
	_p = get_parent()
	var layer := CanvasLayer.new()
	add_child(layer)
	_text = Label.new()
	_text.position = Vector2(12, 12)
	layer.add_child(_text)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_lines = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _lines
	_mi.material_override = mat
	_mi.top_level = true
	add_child(_mi)

	for i in VEC_NAMES.size():
		var t := Label3D.new()
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.no_depth_test = true
		t.font_size = 32
		t.pixel_size = 0.003
		t.modulate = VEC_COLORS[i]
		t.top_level = true
		add_child(t)
		_tags.append(t)
	_set_on(false)


func _web():
	return _p.web_l if _p.web_l.phase == _p.web_l.Phase.ROPE else _p.web_r


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hud"):
		_set_on(not _on)


func _set_on(v: bool) -> void:
	_on = v
	_text.visible = v
	_mi.visible = v
	for t in _tags:
		t.visible = v


func _process(_delta: float) -> void:
	if not _on:
		return
	var origin := _p.global_position + Vector3(0, 1.0, 0)
	var vecs := [_p.f_g, _p.f_n, _p.f_app, _p.f_d, _web().tension_vec(), _p.f_zip]
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in VEC_NAMES.size():
		var tip: Vector3 = origin + vecs[i] * N_TO_M
		_lines.surface_set_color(VEC_COLORS[i])
		_lines.surface_add_vertex(origin)
		_lines.surface_add_vertex(tip)
		_tags[i].global_position = tip
		_tags[i].text = "%s = %.0f N" % [VEC_NAMES[i], vecs[i].length()]
	_lines.surface_end()

	var v: Vector3 = _p.velocity
	var a: Vector3 = _p.accel
	var r: Vector3 = _p.global_position
	var m := CTRL.MASS
	var ke := 0.5 * m * v.length_squared()
	var ug := m * CTRL.G * r.y
	var lines := PackedStringArray()
	lines.append("PHYSICS [F3]   state: %s" % CTRL.STATE_NAMES[_p.state])
	lines.append("Position r = (%.2f, %.2f, %.2f) m" % [r.x, r.y, r.z])
	lines.append("Velocity v = (%.2f, %.2f, %.2f) m/s   |v| = %.2f m/s" % [v.x, v.y, v.z, v.length()])
	lines.append("Acceleration a = (%.2f, %.2f, %.2f) m/s^2" % [a.x, a.y, a.z])
	lines.append("Momentum p = m v = (%.0f, %.0f, %.0f) kg m/s" % [m * v.x, m * v.y, m * v.z])
	lines.append("Energy K = %.0f J   U = %.0f J   E = K+U = %.0f J   lost to drag = %.0f J" % [ke, ug, ke + ug, _p.drag_loss])
	lines.append("Forces: F_g %.0f  F_N %.0f  F_app %.0f  F_d %.0f  net %.0f N" % [_p.f_g.length(), _p.f_n.length(), _p.f_app.length(), _p.f_d.length(), _p.net.length()])
	lines.append("Last event: %s   J = %.0f N s   peak F_N = %.0f N" % [_p.last_event, _p.last_impulse.length(), _p.peak_fn])
	if _p.zip_node.phase != _p.zip_node.Phase.IDLE or _p.zip_node.last_arrival != "":
		var z = _p.zip_node
		var dr: Vector3 = z.last_displacement
		lines.append("ZIP  F_zip = %.0f N   W = F.dr = %.0f J   |dr| = %.2f m" % [z.f_zip.length(), z.work, dr.length()])
		lines.append("Energy dK = %.0f J   dU_g = %.0f J   Impulse |J| = %.0f N s" % [z.last_dk, z.last_du, z.impulse.length()])
	var w = _web()
	if w.phase == w.Phase.ROPE:
		lines.append("Pendulum [%s web]  r = %.2f m   T = %.0f N" % ["left" if w.side < 0.0 else "right", w.last_radius, w.last_tension])
		lines.append("Circular v_tan = %.2f m/s   a_c = v^2/r = %.2f m/s^2   F_c = m v^2/r = %.0f N" % [w.last_vt, w.last_ac, m * w.last_ac])
		lines.append("Motion: non-uniform (speed changes with height along the arc)" if absf(w.last_vt - v.length()) > 0.05 else "Motion: uniform (speed constant along the arc)")
	else:
		lines.append("Circular motion a_c = v^2/r: no web attached (LMB left, RMB right)")
	if DEV:
		var col := "none"
		if _p.get_slide_collision_count() > 0:
			col = str(_p.get_slide_collision(0).get_normal().snapped(Vector3.ONE * 0.01))
		lines.append("DEV grounded=%s airborne=%s fly=%s sprint=%s charging=%s" % [_p.grounded, not _p.grounded, _p.fly, _p.sprint, _p.charging])
		lines.append("DEV diving=%s fast=%s air_peak=%.2f m landing=%s" % [_p.diving, _p.fast, _p.air_peak, _p.landing])
		lines.append("DEV collision normal: %s   floor normal: %s" % [col, _p.get_floor_normal().snapped(Vector3.ONE * 0.01)])
		lines.append("DEV FPS %d   physics %d tick/s   frame %d" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, Engine.get_physics_frames()])
	_text.text = "\n".join(lines)
