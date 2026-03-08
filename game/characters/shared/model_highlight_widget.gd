extends Node2D
class_name ModelHighlightWidget

const CIRCLE_SEGMENTS := 96

@export_range(1.0, 2048.0, 1.0) var radius: float = 200.0:
	set(v):
		radius = max(1.0, v)
		queue_redraw()

@export var center_color: Color = Color(0.2, 0.6, 1.0, 0.28):
	set(v):
		center_color = v
		queue_redraw()

@export var edge_color: Color = Color(0.2, 0.6, 1.0, 0.0):
	set(v):
		edge_color = v
		queue_redraw()

func _draw() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	points.append(Vector2.ZERO)
	colors.append(center_color)
	for i in range(CIRCLE_SEGMENTS + 1):
		var t := float(i) / float(CIRCLE_SEGMENTS)
		var angle := t * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
		colors.append(edge_color)
	draw_polygon(points, colors)

func set_radius(v: float) -> void:
	radius = v

func set_colors(center: Color, edge: Color) -> void:
	center_color = center
	edge_color = edge
