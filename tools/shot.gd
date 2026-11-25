extends SceneTree
## Run the game for N frames in a real window and save a screenshot, for eyeballing model fit.
## Usage: godot --path . -s tools/shot.gd -- /tmp/shot.png [frames] [yaw_deg] [dist]
var _f := 0
var _out := "/tmp/shot.png"
var _frames := 90
var _yaw := 0.0
var _dist := 0.0
var _pitch := 0.15
var _up := 0.0
var _hold := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_frames = int(args[1])
	if args.size() > 2:
		_yaw = deg_to_rad(float(args[2]))
	if args.size() > 3:
		_dist = float(args[3])
	if args.size() > 4:
		_pitch = float(args[4])
	if args.size() > 5:
		_up = float(args[5])
	if args.size() > 6:
		_hold = args[6]  # walk | run | walk_side | run_side: drive the character while shooting
	get_root().add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())


func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		var pivot := get_root().get_node_or_null("Main/Player/Pivot") as Node3D
		var player := get_root().get_node_or_null("Main/Player") as Node3D
		if player and _up > 0.0:
			player.global_position += Vector3.UP * _up  # lift for an overview shot
		if pivot:
			pivot.set("yaw", _yaw)  # orbit_camera re-applies its own yaw every frame
			pivot.set("pitch", _pitch)
			if _dist > 0.0:
				(pivot.get_node("Pitch/Arm") as SpringArm3D).spring_length = _dist
	if _f == 4 and _hold != "":
		Input.action_press("move_right" if _hold.ends_with("side") else "move_forward")
		if _hold.begins_with("run"):
			Input.action_press("sprint")
	if _f < _frames:
		return false
	var img := get_root().get_texture().get_image()
	var err := img.save_png(_out)
	print("saved %s %s (%s)" % [_out, img.get_size(), err])
	return true