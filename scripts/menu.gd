extends Node3D
## Minecraft-style title screen. Gameplay scenes and animation assets remain untouched.

const GAME_SCENE := "res://scenes/main.tscn"
const SPLASH_URL := "https://chardy.dev"
const HELP_ROWS := [
	["W / A / S / D", "Move"],
	["SHIFT", "Sprint / fast dive"],
	["SPACE", "Jump · wall jump · release web"],
	["LEFT CLICK", "Left web"],
	["RIGHT CLICK", "Right web"],
	["LEFT CTRL", "Zip to target"],
	["MOUSE WHEEL", "Zoom camera"],
	["ESC", "Release mouse / pause camera"],
]

@onready var city: Node3D = $City
@onready var avatar: Node3D = $Avatar
@onready var splash: Button = $UI/Margin/VBox/Splash
var help_popup: PanelContainer

func _ready() -> void:
	$UI/Margin/VBox/Buttons/Play.pressed.connect(_play)
	$UI/Margin/VBox/Bottom/Help.pressed.connect(_help)
	$UI/Margin/VBox/Bottom/Quit.pressed.connect(_quit)
	splash.pressed.connect(_open_splash)
	var idle: AnimationPlayer = avatar.get_node_or_null("Rig/AnimationPlayer")
	if idle:
		idle.play("moves/idle")
		idle.seek(0.0, true)

func _process(delta: float) -> void:
	city.rotate_y(delta * 0.012)
	splash.rotation = sin(Time.get_ticks_msec() * 0.004) * 0.025
	splash.scale = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.025)

func _unhandled_input(event: InputEvent) -> void:
	if help_popup and help_popup.visible and event.is_action_pressed("ui_cancel"):
		help_popup.hide()
		get_viewport().set_input_as_handled()

func _play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _help() -> void:
	if help_popup:
		help_popup.show()
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.015, 0.03, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$UI.add_child(overlay)

	help_popup = PanelContainer.new()
	help_popup.name = "HelpPopup"
	help_popup.custom_minimum_size = Vector2(520, 500)
	help_popup.set_anchors_preset(Control.PRESET_CENTER)
	help_popup.position -= help_popup.custom_minimum_size / 2.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.05, 0.085, 0.98)
	panel_style.border_color = Color(0.95, 0.72, 0.18, 1)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 30
	panel_style.content_margin_right = 30
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	help_popup.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(help_popup)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	help_popup.add_child(column)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	column.add_child(title)
	var hint := Label.new()
	hint.text = "KEYBINDS"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.62, 0.7, 0.84))
	column.add_child(hint)
	for row in HELP_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 24)
		var key := Label.new()
		key.text = row[0]
		key.custom_minimum_size.x = 170
		key.add_theme_color_override("font_color", Color(0.95, 0.98, 1))
		key.add_theme_font_size_override("font_size", 18)
		line.add_child(key)
		var action := Label.new()
		action.text = row[1]
		action.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		action.add_theme_font_size_override("font_size", 18)
		line.add_child(action)
		column.add_child(line)
	var close := Button.new()
	close.text = "CLOSE  (ESC)"
	close.custom_minimum_size.y = 48
	close.pressed.connect(func() -> void:
		help_popup.hide()
		overlay.hide())
	column.add_child(close)

func _open_splash() -> void:
	OS.shell_open(SPLASH_URL)

func _quit() -> void:
	get_tree().quit()
