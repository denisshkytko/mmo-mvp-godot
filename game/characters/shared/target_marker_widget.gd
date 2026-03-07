extends Node2D
class_name TargetMarkerWidget

const ELLIPSE_SEGMENTS := 64

@onready var marker_polygon: Polygon2D = %MarkerPolygon
@onready var marker_line: Line2D = %MarkerLine

@export var marker_size: Vector2 = Vector2(44.0, 10.0):
	set(v):
		marker_size = Vector2(max(2.0, v.x), max(2.0, v.y))
		_update_marker_visual()
@export var marker_color: Color = Color(1.0, 0.0, 0.0, 0.54):
	set(v):
		marker_color = v
		_update_marker_visual()
@export var filled: bool = true:
	set(v):
		filled = v
		_update_marker_visual()
@export_range(1.0, 12.0, 0.5) var line_width: float = 2.0:
	set(v):
		line_width = max(1.0, v)
		_update_marker_visual()
@export var antialiased: bool = true:
	set(v):
		antialiased = v
		_update_marker_visual()

func _ready() -> void:
	_update_marker_visual()

func _update_marker_visual() -> void:
	if marker_polygon == null or marker_line == null:
		return

	var points := _build_ellipse_points(marker_size * 0.5)

	marker_polygon.visible = filled
	marker_polygon.polygon = points
	marker_polygon.color = marker_color
	marker_polygon.antialiased = antialiased

	marker_line.visible = not filled
	marker_line.points = points
	marker_line.closed = true
	marker_line.default_color = marker_color
	marker_line.width = line_width
	marker_line.antialiased = antialiased

func _build_ellipse_points(radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(ELLIPSE_SEGMENTS):
		var t := float(i) / float(ELLIPSE_SEGMENTS)
		var angle := t * TAU
		points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points

func get_visual_size() -> Vector2:
	return marker_size

func set_marker_color(color: Color) -> void:
	marker_color = color

func set_marker_size(size: Vector2) -> void:
	marker_size = size
