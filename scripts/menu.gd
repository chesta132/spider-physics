extends Node3D
## Start title screen: spins the city and idles the spider avatar behind the shared menu UI.

const GAME_SCENE := "res://scenes/main.tscn"

@onready var city: Node3D = $City
@onready var avatar: Node3D = $Avatar

func _ready() -> void:
	$UI.play_pressed.connect(_play)
	var idle: AnimationPlayer = avatar.get_node_or_null("Rig/AnimationPlayer")
	if idle:
		idle.play("moves/idle")
		idle.seek(0.0, true)

func _process(delta: float) -> void:
	city.rotate_y(delta * 0.012)

func _play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
