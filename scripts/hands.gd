extends RefCounted
## Hand sockets for web actions. Every web (swing, zip, anything added later) asks this where its
## strand starts, so only the bone names have to survive a rig swap.
## A missing rig, a missing bone or a freed model falls back to a shoulder-height point: a web
## never breaks because of the cosmetic model.

const BONE_L := "Hand.L"
const BONE_R := "Hand.R"
const FALLBACK_X := 0.36   # m, half shoulder width of the 1.8 m rig
const FALLBACK_Y := 1.35   # m, shoulder height
const FALLBACK_Z := 0.10   # m, just in front of the chest

var _player: Node3D
var _skel: Skeleton3D
var _searched := false


func _init(player: Node3D) -> void:
	_player = player


## World position of this hand. `side` follows web.gd: -1 left, +1 right.
func point(side: float) -> Vector3:
	var sk := _rig()
	if sk != null:
		var i := sk.find_bone(BONE_R if side > 0.0 else BONE_L)
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return _fallback(side)


## The rig's skeleton, or null. Cached; re-searched after a rig swap.
func _rig() -> Skeleton3D:
	if _skel != null:
		if is_instance_valid(_skel):
			return _skel
		_skel = null
		_searched = false
	if _searched or not is_instance_valid(_player):
		return null
	_searched = true
	for n in _player.find_children("*", "Skeleton3D", true, false):
		_skel = n as Skeleton3D
		break
	return _skel


## No usable rig: keep the point in the visual's frame so it still turns with the body.
func _fallback(side: float) -> Vector3:
	var off := Vector3(FALLBACK_X * side, FALLBACK_Y, FALLBACK_Z)
	if not is_instance_valid(_player):
		return off
	var frame := _player.get_node_or_null("Visual") as Node3D
	return (frame if frame else _player).global_transform * off
