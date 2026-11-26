extends CanvasLayer
## Title UI shared by the start menu and the in-game pause menu. ESC on this layer emits back_pressed
## only while the layer is visible (pause menu), so the start menu ignores ESC.

signal play_pressed
signal back_pressed

const SPLASH_URL := "https://chardy.dev"
const HELP_ROWS := [
	["W / A / S / D", "Move"],
	["SHIFT", "Sprint / fast dive"],
	["SPACE", "Jump · wall jump · release web"],
	["LEFT CLICK", "Left web"],
	["RIGHT CLICK", "Right web"],
	["LEFT CTRL", "Zip to target"],
	["MOUSE WHEEL", "Zoom camera"],
	["ESC", "Pause / resume game"],
	["F3", "Physics menu"]
]

@export var play_text := "PLAY"
@onready var splash: Button = $Margin/VBox/Splash
var help_overlay: ColorRect

func _ready() -> void:
	$Margin/VBox/Buttons/Play.text = play_text
	$Margin/VBox/Buttons/Play.pressed.connect(play_pressed.emit)
	$Margin/VBox/Bottom/Help.pressed.connect(_help)
	$Margin/VBox/Bottom/Quit.pressed.connect(func() -> void: get_tree().quit())
	splash.pressed.connect(func() -> void: OS.shell_open(SPLASH_URL))

func _process(_delta: float) -> void:
	splash.rotation = sin(Time.get_ticks_msec() * 0.004) * 0.025
	splash.scale = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.025)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if help_overlay and help_overlay.visible:
		help_overlay.hide()
	elif visible:
		back_pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()

func _help() -> void:
	if help_overlay:
		help_overlay.show()
		return
	help_overlay = ColorRect.new()
	help_overlay.color = Color(0.01, 0.015, 0.03, 0.72)
	help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(help_overlay)

	var popup := PanelContainer.new()
	popup.name = "HelpPopup"
	popup.custom_minimum_size = Vector2(520, 500)
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.position -= popup.custom_minimum_size / 2.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.05, 0.085, 0.98)
	panel_style.border_color = Color(0.95, 0.72, 0.18, 1)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 30
	panel_style.content_margin_right = 30
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	popup.add_theme_stylebox_override("panel", panel_style)
	help_overlay.add_child(popup)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	popup.add_child(column)
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
	close.pressed.connect(help_overlay.hide)
	column.add_child(close)
