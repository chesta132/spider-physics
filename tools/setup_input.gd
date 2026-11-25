extends SceneTree
## One-time setup: writes the Input Map and main scene into project.godot.
## Run: godot --headless -s tools/setup_input.gd

func _initialize() -> void:
	# Step 1 actions
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("sprint", KEY_SHIFT)
	_key("jump", KEY_SPACE)
	_key("debug_hud", KEY_F3)
	_key("debug_fly", KEY_F4)  # dev-only; ignored in release builds
	_mouse("cam_zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_mouse("cam_zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	# Registered for later steps, not implemented yet
	_mouse("web_left", MOUSE_BUTTON_LEFT)
	_mouse("web_right", MOUSE_BUTTON_RIGHT)
	_key("zip", KEY_CTRL)  # Step 4: zip to point / perch (Ctrl)
	_key("super_jump", KEY_SPACE)
	_key("fast_dive", KEY_SHIFT)
	_key("wall_detach", KEY_SPACE)
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main.tscn")
	var err := ProjectSettings.save()
	print("project.godot saved: ", err == OK)
	quit()


func _bind(action: String, ev: InputEvent) -> void:
	ev.device = -1  # match every input device
	ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": [ev]})


func _key(action: String, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	_bind(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	_bind(action, ev)
