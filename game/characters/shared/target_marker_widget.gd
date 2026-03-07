extends Node2D
class_name TargetMarkerWidget

const ELLIPSE_SEGMENTS := 64

@export_range(1.0, 512.0, 0.5) var radius_x: float = 22.0:
	set(v):
		radius_x = max(1.0, v)
		queue_redraw()

@export_range(1.0, 512.0, 0.5) var radius_y: float = 5.0:
	set(v):
		radius_y = max(1.0, v)
		queue_redraw()

@export_range(-512.0, 512.0, 0.5) var y_offset: float = 0.0:
	set(v):
		y_offset = v
		queue_redraw()

@export var marker_color: Color = Color(1.0, 0.0, 0.0, 0.54):
	set(v):
		marker_color = v
		queue_redraw()

func _draw() -> void:
	var points := _build_ellipse_points()
	if points.size() >= 3:
		draw_colored_polygon(points, marker_color)

func _build_ellipse_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var t := float(i) / float(ELLIPSE_SEGMENTS)
		var angle := t * TAU
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y + y_offset))
	return points

func get_visual_size() -> Vector2:
	return Vector2(radius_x * 2.0, radius_y * 2.0)

func set_marker_color(color: Color) -> void:
	marker_color = color

func set_marker_size(size: Vector2) -> void:
	radius_x = max(1.0, size.x * 0.5)
	radius_y = max(1.0, size.y * 0.5)
	queue_redraw()
