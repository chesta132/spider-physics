extends Node3D
## Map host. With map_scene set, that scene is instanced under Greybox and the player is moved onto
## its Spawn marker. With it empty, a procedural greybox is built instead.

@export var map_scene: PackedScene

# [center_x, center_z, size_x, height, size_z]
const BLOCKS := [
	[10, 0, 6, 8, 6],
	[-12, 4, 5, 15, 5],
	[0, -14, 8, 4, 8],
	[16, -10, 4, 25, 4],
	[-6, 6, 3, 1.0, 3],
	[-20, -8, 6, 3, 6],
	[26, 4, 4, 0.5, 10],
	[-30, 0, 8, 40, 8],  # tall platform for high super-jump dives (Step 2)
]


func _ready() -> void:
	if map_scene:
		var map := map_scene.instantiate()
		$Greybox.add_child(map)
		var spawn := map.get_node_or_null("Spawn") as Node3D
		if spawn:
			$Player.global_position = spawn.global_position
		return
	_box(Vector3(0, -0.5, 0), Vector3(300, 1, 300), Color(0.35, 0.35, 0.37))
	for b in BLOCKS:
		var h: float = b[3]
		_box(Vector3(b[0], h / 2.0, b[1]), Vector3(b[2], h, b[4]), Color.from_hsv(0.6, 0.15, 0.4 + h / 50.0))
	_zip_course()


## Step 4 test course: tiered rooftops, a gapped tower pair, a tall wall, and an overhanging arch.
func _zip_course() -> void:
	var tier := Color(0.45, 0.62, 0.75)
	# Multi-tier rooftop: low, medium, tall ledges to zip onto and vault over.
	_box(Vector3(40, 2.0, 0), Vector3(10, 4, 10), tier)
	_box(Vector3(40, 4.5, 0), Vector3(7, 9, 7), tier.lightened(0.1))
	_box(Vector3(40, 7.0, 0), Vector3(4, 14, 4), tier.lightened(0.2))
	# Separated towers with a gap: mid-air diagonal zips between them.
	_box(Vector3(52, 6.0, 20), Vector3(5, 12, 5), tier)
	_box(Vector3(66, 8.0, 20), Vector3(5, 16, 5), tier.lightened(0.1))
	# Tall thin wall face: zip onto a vertical surface.
	_box(Vector3(40, 10.0, -22), Vector3(1.2, 20, 14), tier.darkened(0.1))
	# Thin perch pillars: every top point is near an edge, so outer-corner hints register easily.
	_box(Vector3(74, 5.0, 20), Vector3(2, 10, 2), tier.lightened(0.15))
	_box(Vector3(78, 8.0, 27), Vector3(2, 16, 2), tier.lightened(0.2))
	# Tall wide wall with no roof inside zip range: the no-perch boost target.
	_box(Vector3(90, 30, 20), Vector3(6, 60, 12), tier.darkened(0.15))
	# Rooftop slab with clean outer corners to perch on.
	_box(Vector3(80, 12.0, 20), Vector3(7, 0.8, 7), tier)
	# Overhanging archway: two pillars and a slab, zip up onto the perch.
	_box(Vector3(52, 5.0, -22), Vector3(1.5, 10, 1.5), tier.darkened(0.2))
	_box(Vector3(60, 5.0, -22), Vector3(1.5, 10, 1.5), tier.darkened(0.2))
	_box(Vector3(56, 10.6, -22), Vector3(12, 1.2, 6), tier.lightened(0.05))


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mesh.mesh = bm
	body.add_child(shape)
	body.add_child(mesh)
	$Greybox.add_child(body)
