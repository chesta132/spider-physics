extends SceneTree
## Rebind zip to Left Ctrl only (webs keep LMB/RMB).
func _initialize() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_CTRL
	k.device = -1
	ProjectSettings.set_setting("input/zip", {"deadzone": 0.5, "events": [k]})
	print("saved: ", ProjectSettings.save() == OK)
	quit()
