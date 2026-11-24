extends Node3D
## Greybox test map: flat ground plus dummy blocks of varying height.
## Replace the Greybox node's children with the real map later; nothing else depends on them.

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
	_box(Vector3(0, -0.5, 0), Vector3(300, 1, 300), Color(0.35, 0.35, 0.37))
	for b in BLOCKS:
		var h: float = b[3]
		_box(Vector3(b[0], h / 2.0, b[1]), Vector3(b[2], h, b[4]), Color.from_hsv(0.6, 0.15, 0.4 + h / 50.0))


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
