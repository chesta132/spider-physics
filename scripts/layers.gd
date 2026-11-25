extends RefCounted
## Collision layers, as bit values (the editor shows them 1-indexed).
## WORLD is everything a gameplay ray may target: the map and the greybox.
## BOUNDARY is the invisible perimeter shell: solid for the player body, invisible to every
## web / zip / wall probe, so a web never anchors to thin air at the map edge.
## The player's mask in scenes/player.tscn is WORLD | BOUNDARY = 5.
## Loaded with `const Layers := preload("res://scripts/layers.gd")` rather than a class_name, so a
## headless run never depends on the editor's global class cache being up to date.

const WORLD := 1        # layer 1
const PLAYER := 2       # layer 2
const BOUNDARY := 4     # layer 3

const WORLD_MASK := WORLD
const PLAYER_MASK := WORLD | BOUNDARY


## Every gameplay ray goes through here, so the boundary can never be hit by accident.
static func ray(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = WORLD_MASK
	return q