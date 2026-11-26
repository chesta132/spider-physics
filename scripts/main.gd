extends Node3D
## Map host. With map_scene set, that scene is instanced under Greybox and the player is moved onto
## its Spawn marker. With it empty, a procedural greybox is built instead.

@export var map_scene: PackedScene
var pause_layer: CanvasLayer
var pause_panel: PanelContainer
var pause_camera: Camera3D
var gameplay_camera: Camera3D
var pause_tween: Tween

# [center_x, center_z, size_x, height, size_z]
const BLOCKS := [
	[10, 0, 6, 8, 6],
	[-12, 4, 5, 15, 5],
	[0, -14, 8, 4, 8],
	[16, -10, 4, 25, 4],
	[-6, 6, 3, 1.0, 3],
	[-20, -8, 6, 3, 6],
	[26, 4, 4, 0.5, 10],
	[-30, 0, 8, 40, 8],  # tall platform for high super-jump dives (Step 2)
]


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") and not get_tree().paused:
		_toggle_pause()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and get_tree().paused:
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if not pause_layer:
		return
	var opening := not get_tree().paused
	get_tree().paused = opening
	pause_layer.visible = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
	if opening:
		_pause_camera_transition()
	else:
		gameplay_camera.current = true

func _pause_camera_transition() -> void:
	var player := $Player
	var target := player.global_position + Vector3(3.8, 2.4, 5.2)
	pause_camera.global_position = gameplay_camera.global_position
	pause_camera.look_at(player.global_position + Vector3.UP * 1.0)
	pause_camera.current = true
	if pause_tween:
		pause_tween.kill()
	pause_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pause_tween.set_parallel()
	pause_tween.tween_property(pause_camera, "global_position", target, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pause_tween.tween_method(_aim_pause_camera.bind(player), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _aim_pause_camera(_weight: float, player: Node3D) -> void:
	pause_camera.look_at(player.global_position + Vector3.UP * 0.9)

func _create_pause_ui() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.visible = false
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.64)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(dim)
	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(500, 330)
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position -= pause_panel.custom_minimum_size / 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.05, 0.94)
	style.border_color = Color(0.55, 0.62, 0.75, 1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	pause_panel.add_theme_stylebox_override("panel", style)
	dim.add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	pause_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1))
	box.add_child(title)
	var continue_button := Button.new()
	continue_button.text = "CONTINUE"
	continue_button.custom_minimum_size.y = 64
	continue_button.add_theme_font_size_override("font_size", 26)
	continue_button.pressed.connect(_toggle_pause)
	box.add_child(continue_button)
	var help := Label.new()
	help.text = "ESC  Resume"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	box.add_child(help)
	pause_camera = Camera3D.new()
	pause_camera.name = "PauseCamera"
	add_child(pause_camera)
	pause_camera.current = false
func _ready() -> void:
	gameplay_camera = $Player/Pivot/Pitch/Arm/Camera
	_create_pause_ui()
	if map_scene:
		var map := map_scene.instantiate()
		$Greybox.add_child(map)
		var spawn := map.get_node_or_null("Spawn") as Node3D
		if spawn:
			$Player.global_position = spawn.global_position
		return
	_box(Vector3(0, -0.5, 0), Vector3(300, 1, 300), Color(0.35, 0.35, 0.37))
	for b in BLOCKS:
		var h: float = b[3]
		_box(Vector3(b[0], h / 2.0, b[1]), Vector3(b[2], h, b[4]), Color.from_hsv(0.6, 0.15, 0.4 + h / 50.0))
	_zip_course()


## Step 4 test course: tiered rooftops, a gapped tower pair, a tall wall, and an overhanging arch.
func _zip_course() -> void:
	var tier := Color(0.45, 0.62, 0.75)
	# Multi-tier rooftop: low, medium, tall ledges to zip onto and vault over.
	_box(Vector3(40, 2.0, 0), Vector3(10, 4, 10), tier)
	_box(Vector3(40, 4.5, 0), Vector3(7, 9, 7), tier.lightened(0.1))
	_box(Vector3(40, 7.0, 0), Vector3(4, 14, 4), tier.lightened(0.2))
	# Separated towers with a gap: mid-air diagonal zips between them.
	_box(Vector3(52, 6.0, 20), Vector3(5, 12, 5), tier)
	_box(Vector3(66, 8.0, 20), Vector3(5, 16, 5), tier.lightened(0.1))
	# Tall thin wall face: zip onto a vertical surface.
	_box(Vector3(40, 10.0, -22), Vector3(1.2, 20, 14), tier.darkened(0.1))
	# Thin perch pillars: every top point is near an edge, so outer-corner hints register easily.
	_box(Vector3(74, 5.0, 20), Vector3(2, 10, 2), tier.lightened(0.15))
	_box(Vector3(78, 8.0, 27), Vector3(2, 16, 2), tier.lightened(0.2))
	# Tall wide wall with no roof inside zip range: the no-perch boost target.
	_box(Vector3(90, 30, 20), Vector3(6, 60, 12), tier.darkened(0.15))
	# Rooftop slab with clean outer corners to perch on.
	_box(Vector3(80, 12.0, 20), Vector3(7, 0.8, 7), tier)
	# Overhanging archway: two pillars and a slab, zip up onto the perch.
	_box(Vector3(52, 5.0, -22), Vector3(1.5, 10, 1.5), tier.darkened(0.2))
	_box(Vector3(60, 5.0, -22), Vector3(1.5, 10, 1.5), tier.darkened(0.2))
	_box(Vector3(56, 10.6, -22), Vector3(12, 1.2, 6), tier.lightened(0.05))


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mesh.mesh = bm
	body.add_child(shape)
	body.add_child(mesh)
	$Greybox.add_child(body)
