extends Control

var _points: Array[Dictionary] = []
var _outline_color: Color = Color(0, 0, 0, 1)


func set_points(points: Array[Dictionary], outline_color: Color) -> void:
	_points = points
	_outline_color = outline_color
	queue_redraw()


func _draw() -> void:
	for item in _points:
		var p: Vector2 = item.get("pos", Vector2.ZERO) as Vector2
		var r: float = float(item.get("radius", 2.0))
		var c: Color = item.get("color", Color.WHITE) as Color
		draw_circle(p, r + 1.0, _outline_color)
		draw_circle(p, r, c)
