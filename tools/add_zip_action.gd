extends SceneTree
## One-off: add the zip action (E and Middle Mouse) to project.godot.
func _initialize() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_E
	k.device = -1
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	m.pressed = true
	m.device = -1
	ProjectSettings.set_setting("input/zip", {"deadzone": 0.5, "events": [k, m]})
	print("saved: ", ProjectSettings.save() == OK)
	quit()
