extends CanvasLayer
## Title UI shared by the start menu and the in-game pause menu. ESC on this layer emits back_pressed
## only while the layer is visible (pause menu), so the start menu ignores ESC.

signal play_pressed
signal back_pressed

const SPLASH_URL := "https://chardy.dev"
const HELP_ROWS := [
	["W / A / S / D", "Move"],
	["SHIFT", "Sprint / fast dive"],
	["SPACE", "Jump / wall jump / release web"],
	["HOLD SPACE", "Charge jump"],
	["LEFT CLICK", "Left web"],
	["RIGHT CLICK", "Right web"],
	["LEFT CTRL", "Zip to target"],
	["MOUSE WHEEL", "Zoom camera"],
	["ESC", "Pause / resume game"],
	["F3", "Physics menu"]
]
const CREDIT_ROWS := [
	["Developer", "Chesta"],
	["Developer", "Syafiq"],
	["Developer", "Tyas"],
	["Developer", "Faiq"],
	["Map", "Sketchfab", "https://sketchfab.com/3d-models/map-02-new-york-driving-school-2016-fa9f2d770b894028a85cf1636091af44"],
	["Avatar", "Sketchfab", "https://sketchfab.com/3d-models/lego-spiderman-a8acef5e02214bdd8360b003bfea5292"],
	["Background Music", "OpenGameArt", "https://opengameart.org/content/jetstream-joyride-looping"],
	["SFXs", "OpenGameArt", "https://opengameart.org"]
]

const FONT_PATH := "res://assets/ui/Minecraft.ttf"
const TEXT_DARK := Color(0.17, 0.17, 0.19)
const SPLASH_ANGLE := -0.314159
const LINK_COLOR := Color(0.55, 0.75, 1.0)
const LINK_HOVER_ALPHA := 0.6

@export var play_text := "PLAY"
@onready var splash: Button = $Root/Title/Splash
@onready var title: Control = $Root/Title
@onready var buttons: Array[Button] = [$Root/Buttons/Play, $Root/Buttons/Help,$Root/Buttons/Credit, $Root/Buttons/Quit]
var panel_overlay: Control
var font: Font
var font_bold: Font

func _ready() -> void:
	font = load(FONT_PATH)
	font_bold = font
	var title_font := FontVariation.new()
	title_font.base_font = font
	title_font.variation_embolden = 0.3
	title.set("font", title_font)
	title.queue_redraw()
	$Root/Buttons/Play.text = play_text
	$Root/Buttons/Play.pressed.connect(play_pressed.emit)
	$Root/Buttons/Help.pressed.connect(_help)
	$Root/Buttons/Credit.pressed.connect(_credit)
	$Root/Buttons/Quit.pressed.connect(func() -> void: get_tree().quit())
	splash.pressed.connect(func() -> void: OS.shell_open(SPLASH_URL))
	for b in buttons:
		_style_button(b, 32)
	_style_splash()
	var footer: Label = $Root/Footer
	footer.add_theme_font_override("font", font)
	footer.add_theme_font_size_override("font_size", 16)
	footer.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	footer.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	footer.add_theme_constant_override("shadow_offset_x", 2)
	footer.add_theme_constant_override("shadow_offset_y", 2)
	title.resized.connect(_place_splash)
	_place_splash()

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	splash.rotation = SPLASH_ANGLE + sin(t * 4.0) * 0.02
	splash.scale = Vector2.ONE * (1.0 + sin(t * 6.0) * 0.04)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if panel_overlay and is_instance_valid(panel_overlay):
		_close_panel()
	elif visible:
		back_pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()

## Splash sits on the lower-right corner of the logo, tilted, like the Minecraft one.
func _place_splash() -> void:
	splash.size = splash.get_minimum_size()
	splash.pivot_offset = splash.size * 0.5
	splash.position = Vector2(title.size.x - 120.0, title.size.y - 26.0) - splash.size * 0.5

func _style_splash() -> void:
	splash.add_theme_font_override("font", font)
	splash.add_theme_font_size_override("font_size", 24)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		splash.add_theme_color_override(c, Color(1.0, 1.0, 0.33))
	splash.add_theme_color_override("font_outline_color", Color(0.18, 0.18, 0.0))
	splash.add_theme_constant_override("outline_size", 6)
	splash.focus_mode = Control.FOCUS_NONE

## Pixel-art bevel (2px "pixels") stretched as a 9-slice: dark edge, lit top/left, shaded bottom/right.
func _bevel(fill: Color, light: Color, shade: Color, edge: Color) -> StyleBoxTexture:
	const U := 2
	const N := 8
	var img := Image.create_empty(N * U, N * U, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var c := fill
			if x == 0 or y == 0 or x == N - 1 or y == N - 1:
				c = edge
			elif x == 1 or y == 1:
				c = light
			elif y >= N - 3 or x == N - 2:
				c = shade
			img.fill_rect(Rect2i(x * U, y * U, U, U), c)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	box.texture_margin_left = 3 * U
	box.texture_margin_right = 3 * U
	box.texture_margin_top = 3 * U
	box.texture_margin_bottom = 3 * U
	box.content_margin_left = 12
	box.content_margin_right = 12
	return box

func _style_button(b: Button, size: int) -> void:
	var normal := _bevel(Color(0.70, 0.70, 0.72), Color(0.93, 0.93, 0.95), Color(0.42, 0.42, 0.46), Color(0.07, 0.07, 0.09))
	var hover := _bevel(Color(0.62, 0.68, 0.88), Color(0.86, 0.9, 1.0), Color(0.33, 0.38, 0.6), Color(1, 1, 1))
	var pressed := _bevel(Color(0.52, 0.52, 0.56), Color(0.36, 0.36, 0.4), Color(0.7, 0.7, 0.74), Color(0.07, 0.07, 0.09))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, TEXT_DARK)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.06, 0.1))

func _help() -> void:
	show_panel("HOW TO PLAY", "KEYBINDS", HELP_ROWS)

func _credit() -> void:
	show_panel("CREDITS", "SPECIAL THANKS TO", CREDIT_ROWS)

func _make_link(label: Label, url: String) -> void:
	label.add_theme_color_override("font_color", LINK_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.tooltip_text = url
	label.mouse_entered.connect(func() -> void: label.modulate.a = LINK_HOVER_ALPHA)
	label.mouse_exited.connect(func() -> void: label.modulate.a = 1.0)
	label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url))

func show_panel(heading_text: String, hint_text: String, rows_data: Array, close_text := "CLOSE  (ESC)") -> void:
	_close_panel()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel_overlay = overlay
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var popup := PanelContainer.new()
	popup.name = "HelpPopup"
	popup.custom_minimum_size = Vector2(560, 0)
	popup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var panel := _bevel(Color(0.70, 0.70, 0.72), Color(0.93, 0.93, 0.95), Color(0.42, 0.42, 0.46), Color(0.07, 0.07, 0.09))
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 26
	panel.content_margin_bottom = 26
	popup.add_theme_stylebox_override("panel", panel)
	center.add_child(popup)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	popup.add_child(column)
	var heading := Label.new()
	heading.text = heading_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", font_bold)
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", TEXT_DARK)
	column.add_child(heading)
	if not hint_text.is_empty():
		var hint := Label.new()
		hint.text = hint_text
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_override("font", font)
		hint.add_theme_font_size_override("font_size", 16)
		hint.add_theme_color_override("font_color", Color(0.32, 0.32, 0.38))
		column.add_child(hint)
	var rows := PanelContainer.new()
	rows.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var inset := _bevel(Color(0.30, 0.30, 0.33), Color(0.22, 0.22, 0.25), Color(0.42, 0.42, 0.46), Color(0.07, 0.07, 0.09))
	inset.content_margin_left = 22
	inset.content_margin_right = 22
	inset.content_margin_top = 16
	inset.content_margin_bottom = 16
	rows.add_theme_stylebox_override("panel", inset)
	column.add_child(rows)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	rows.add_child(list)
	for row in rows_data:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 20)
		var key := Label.new()
		key.text = row[0]
		key.custom_minimum_size.x = 190
		key.add_theme_font_override("font", font_bold)
		key.add_theme_font_size_override("font_size", 16)
		key.add_theme_color_override("font_color", Color(1.0, 1.0, 0.45))
		line.add_child(key)
		var action := Label.new()
		action.text = row[1]
		action.add_theme_font_override("font", font)
		action.add_theme_font_size_override("font_size", 16)
		action.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
		if row.size() > 2:
			_make_link(action, row[2])
		line.add_child(action)
		list.add_child(line)
	var close := Button.new()
	close.text = close_text
	close.custom_minimum_size.y = 52
	_style_button(close, 24)
	close.pressed.connect(_close_panel)
	column.add_child(close)

func _close_panel() -> void:
	if panel_overlay and is_instance_valid(panel_overlay):
		panel_overlay.queue_free()
	panel_overlay = null
