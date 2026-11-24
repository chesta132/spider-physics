extends Node3D
## Third-person orbit pivot. Child of the player body, so it rides the body's physics-interpolated transform.
## Yaw here is camera-only. The player's facing is set from velocity in player_controller.gd.

@export var sensitivity := 0.0025

const ZOOM_STEP := 0.75
const MIN_DIST := 1.5
const MAX_DIST := 20.0
const PITCH_MIN := -0.6
const PITCH_MAX := deg_to_rad(89)  # stop short of the gimbal flip at 90 degrees

var yaw := 0.0
var pitch := 0.35

@onready var pitch_node: Node3D = $Pitch
@onready var arm: SpringArm3D = $Pitch/Arm


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch = clampf(pitch + event.relative.y * sensitivity, PITCH_MIN, PITCH_MAX)  # mouse down raises camera (inverted)
	elif event.is_action_pressed("cam_zoom_in"):
		arm.spring_length = maxf(arm.spring_length - ZOOM_STEP, MIN_DIST)
	elif event.is_action_pressed("cam_zoom_out"):
		arm.spring_length = minf(arm.spring_length + ZOOM_STEP, MAX_DIST)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	rotation.y = yaw
	pitch_node.rotation.x = -pitch  # arm points +Z; negative X lifts the camera above the pivot
