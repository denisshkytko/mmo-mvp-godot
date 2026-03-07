extends Node2D
class_name TargetMarkerWidget

@export var marker_size: Vector2 = Vector2(44.0, 10.0):
	set(v):
		marker_size = Vector2(max(2.0, v.x), max(2.0, v.y))
		queue_redraw()
@export var marker_color: Color = Color(1.0, 0.0, 0.0, 0.54):
	set(v):
		marker_color = v
		queue_redraw()
@export var filled: bool = true:
	set(v):
		filled = v
		queue_redraw()
@export_range(1.0, 12.0, 0.5) var line_width: float = 2.0:
	set(v):
		line_width = max(1.0, v)
		queue_redraw()
@export var antialiased: bool = true:
	set(v):
		antialiased = v
		queue_redraw()

func _draw() -> void:
	var radius := marker_size * 0.5
	if filled:
		draw_ellipse(Vector2.ZERO, radius, marker_color)
	else:
		var points: PackedVector2Array = []
		var segments := 64
		for i in range(segments + 1):
			var t := float(i) / float(segments)
			var a := t * TAU
			points.append(Vector2(cos(a) * radius.x, sin(a) * radius.y))
		draw_polyline(points, marker_color, line_width, antialiased)

func get_visual_size() -> Vector2:
	return marker_size

func set_marker_color(color: Color) -> void:
	marker_color = color

func set_marker_size(size: Vector2) -> void:
	marker_size = size
