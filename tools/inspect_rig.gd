extends SceneTree
## Lists the rig so Step 7 can wire animation, IK and web-hand anchors off real names:
## every AnimationPlayer clip with its length and track count, and the Skeleton3D bone tree with
## each bone's world rest position (glTF space — the player scene shifts Model by -1.05 on X).
## Usage: godot --headless -s tools/inspect_rig.gd

const MODEL := "res://assets/player/scene.gltf"

var _root: Node
var _frames := 0


func _initialize() -> void:
	_root = (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(_root)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false  # global transforms resolve one frame after entering the tree
	_report()
	return true


func _report() -> void:
	var players: Array = []
	var skels: Array = []
	var stack: Array = [_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			players.append(n)
		if n is Skeleton3D:
			skels.append(n)
		stack.append_array(n.get_children())

	print("=== ", MODEL)
	print("AnimationPlayer nodes: %d" % players.size())
	for ap in players:
		var p := ap as AnimationPlayer
		var names := p.get_animation_list()
		print("  %s  (%d clip(s))" % [p.name, names.size()])
		for nm in names:
			var a: Animation = p.get_animation(nm)
			print("    %-34s %.2f s  %d tracks" % [nm, a.length, a.get_track_count()])
	if players.is_empty():
		print("  (none — the glTF carries no clips; this is a static bind-pose rig)")

	for s in skels:
		var sk := s as Skeleton3D
		print("\nSkeleton3D '%s': %d bones" % [sk.name, sk.get_bone_count()])
		print("%3s  %-32s %-32s %-24s %s" % ["idx", "bone", "parent", "world rest pos", "role"])
		for i in sk.get_bone_count():
			var bn := sk.get_bone_name(i)
			var pi := sk.get_bone_parent(i)
			var pname := sk.get_bone_name(pi) if pi >= 0 else "-"
			var t: Transform3D = sk.global_transform * sk.get_bone_global_rest(i)
			print("%3d  %-32s %-32s (%7.3f, %7.3f, %7.3f)  %s" % [
				i, bn, pname, t.origin.x, t.origin.y, t.origin.z, _role(bn)])

	print("\n--- Step 7 anchor candidates ---")
	for pat in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftHand", "RightHand",
			"LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		for i in skels[0].get_bone_count():
			var bn: String = skels[0].get_bone_name(i)
			if bn.contains(pat) and not bn.contains("end") and not bn.contains("_end"):
				var t: Transform3D = skels[0].global_transform * skels[0].get_bone_global_rest(i)
				print("  %-12s -> %-32s pos (%.3f, %.3f, %.3f)" % [
					pat, bn, t.origin.x, t.origin.y, t.origin.z])
				break


func _role(bn: String) -> String:
	var low := bn.to_lower()
	for key in ["hips", "spine", "neck", "head", "hand", "foot", "toe", "shoulder", "arm", "leg"]:
		if low.contains(key):
			return key
	return ""


