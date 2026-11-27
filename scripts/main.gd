extends Node3D
const Sound := preload("res://scripts/sound.gd")
## Map host. With map_scene set, that scene is instanced under Greybox and the player is moved onto
## its Spawn marker. With it empty, a procedural greybox is built instead.

@export var map_scene: PackedScene
var pause_ui: CanvasLayer
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
var menu_sound = preload("res://assets/sounds/background_music.mp3")
var menu_player: AudioStreamPlayer
var ambient_sound = preload("res://assets/sounds/city_ambient.mp3")
var ambient_player: AudioStreamPlayer

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	var opening := not get_tree().paused
	get_tree().paused = opening
	pause_ui.visible = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED
	if opening:
		_pause_camera_transition()
		ambient_player.stream_paused = true
		menu_player.stream_paused = false
	else:
		_resume_camera_transition()
		menu_player.stream_paused = true
		ambient_player.stream_paused = false

## Tweens from gameplay view to a camera placed where the start-menu camera sits relative to its avatar
## (menu.tscn: Avatar at (5.5, 0, 7.5), yaw -30, scale 2; Camera at (0, 4, 14)), applied to the player's
## Visual node. The camera then looks straight at the spider's chest, so it stays face to face.
func _pause_camera_transition() -> void:
	var visual: Node3D = $Player/Visual
	var menu_avatar := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-30), 0)).scaled(Vector3(2, 2, 2)), Vector3(5.5, 0, 7.5))
	var menu_camera := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-8), 0, 0)), Vector3(0, 4, 14))
	var target := visual.global_transform * (menu_avatar.affine_inverse() * menu_camera)
	target.basis = target.basis.orthonormalized()
	var from := gameplay_camera.global_transform
	pause_camera.global_transform = from
	pause_camera.current = true
	if pause_tween:
		pause_tween.kill()
	pause_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pause_tween.tween_method(func(w: float) -> void: pause_camera.global_transform = from.interpolate_with(target, w), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Tweens from the pause view back to the live gameplay camera, then hands control back to it.
func _resume_camera_transition() -> void:
	var from := pause_camera.global_transform
	if pause_tween:
		pause_tween.kill()
	pause_tween = create_tween()
	pause_tween.tween_method(func(w: float) -> void: pause_camera.global_transform = from.interpolate_with(gameplay_camera.global_transform, w), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	pause_tween.tween_callback(func() -> void: gameplay_camera.current = true)

func _ready() -> void:
	menu_sound.loop = true
	menu_player = AudioStreamPlayer.new()
	menu_player.stream = menu_sound
	menu_player.volume_db = -15
	menu_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_player)
	menu_player.play()
	menu_player.stream_paused = true

	ambient_sound.loop = true
	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = ambient_sound
	ambient_player.volume_db = -15
	ambient_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ambient_player)
	ambient_player.play()

	gameplay_camera = $Player/Pivot/Pitch/Arm/Camera
	pause_camera = Camera3D.new()
	pause_camera.name = "PauseCamera"
	add_child(pause_camera)
	pause_ui = preload("res://scenes/menu_ui.tscn").instantiate()
	pause_ui.play_text = "CONTINUE"
	pause_ui.layer = 20
	pause_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_ui.visible = false
	pause_ui.play_pressed.connect(_toggle_pause)
	pause_ui.back_pressed.connect(_toggle_pause)
	add_child(pause_ui)
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
