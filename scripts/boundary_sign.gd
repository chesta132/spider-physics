extends Node3D
## One "Do Not Enter" panel on the barrier's playable face.
## Invisible beyond FADE_FAR metres from the player and faded in smoothly below that, with the
## gradient falling off across the panel itself (see shaders/do_not_enter.gdshader). The label's
## alpha uses the same curve, so text and panel never disagree.

const FADE_NEAR := 18.0   # m, fully opaque inside this
const FADE_FAR := 55.0    # m, fully invisible beyond this

var size := Vector2(3.0, 1.6)  # m, set by world_boundary before the node enters the tree

var _mesh: MeshInstance3D
var _label: Label3D
var _mat: ShaderMaterial
var _player: Node3D


## Same curve as the shader, so a test can assert the falloff without rendering.
static func fade_for(dist: float) -> float:
	return 1.0 - smoothstep(FADE_NEAR, FADE_FAR, dist)


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D

	var q := QuadMesh.new()
	q.size = size
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/do_not_enter.gdshader")
	_mat.set_shader_parameter("sign_size", size)
	_mat.set_shader_parameter("fade_near", FADE_NEAR)
	_mat.set_shader_parameter("fade_far", FADE_FAR)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = q
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_label = Label3D.new()
	_label.text = "DO NOT ENTER"
	_label.font_size = 128
	_label.pixel_size = 0.0042
	_label.outline_size = 28
	_label.outline_modulate = Color(0.06, 0.06, 0.07)
	_label.modulate = Color(1, 1, 1, 0)
	_label.position = Vector3(0, 0, 0.02)
	add_child(_label)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var d := global_position.distance_to(_player.global_position)
	var a := fade_for(d)
	_mat.set_shader_parameter("player_pos", _player.global_position)
	_label.modulate.a = a
	visible = a > 0.001  # nothing to draw (or shade) while it is out of range
