extends Control
## Blocky "logo" title: black outline, stacked dark extrusion, stone-grey face with a lit top-left edge.

@export var text := "SPIDER-PHYSICS"
@export var font: Font
@export var font_size := 96
@export var depth := 6

const FACE := Color(0.74, 0.74, 0.76)
const LIGHT := Color(0.96, 0.96, 0.98)
const EXTRUDE_NEAR := Color(0.36, 0.36, 0.4)
const EXTRUDE_FAR := Color(0.12, 0.12, 0.15)
const EDGE := Color(0.04, 0.04, 0.06)

func _draw() -> void:
	if font == null:
		return
	var size_px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := Vector2((size.x - size_px.x - depth) * 0.5, (size.y - depth) * 0.5 + font.get_ascent(font_size) - size_px.y * 0.5)
	for i in range(depth, 0, -1):
		var t := float(i - 1) / maxf(depth - 1, 1)
		var p := origin + Vector2(i, i)
		if i == depth:
			draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, EDGE)
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, EXTRUDE_NEAR.lerp(EXTRUDE_FAR, t))
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, EDGE)
	draw_string(font, origin + Vector2(-2, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LIGHT)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, FACE)
