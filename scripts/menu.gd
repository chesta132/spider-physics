extends Node3D
## Minecraft-style title screen. Gameplay scenes and animation assets remain untouched.

const GAME_SCENE := "res://scenes/main.tscn"
const SPLASH_URL := "https://chardy.dev"

@onready var city: Node3D = $City
@onready var avatar: Node3D = $Avatar
@onready var splash: Button = $UI/Margin/VBox/Splash

func _ready() -> void:
	$UI/Margin/VBox/Buttons/Play.pressed.connect(_play)
	$UI/Margin/VBox/Buttons/Settings.pressed.connect(_settings)
	$UI/Margin/VBox/Bottom/Help.pressed.connect(_help)
	$UI/Margin/VBox/Bottom/Quit.pressed.connect(_quit)
	splash.pressed.connect(_open_splash)
	var idle: AnimationPlayer = avatar.get_node_or_null("AnimationPlayer")
	if idle and idle.has_animation("moves/idle"):
		idle.play("moves/idle")

func _process(delta: float) -> void:
	city.rotate_y(delta * 0.012)
	splash.rotation = sin(Time.get_ticks_msec() * 0.004) * 0.025
	splash.scale = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.025)

func _play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _settings() -> void:
	$UI/Margin/VBox/Buttons/Settings.text = "SETTINGS (COMING SOON)"

func _help() -> void:
	$UI/Margin/VBox/Bottom/Help.text = "HELP: WASD · SPACE · WEB"

func _open_splash() -> void:
	OS.shell_open(SPLASH_URL)

func _quit() -> void:
	get_tree().quit()
