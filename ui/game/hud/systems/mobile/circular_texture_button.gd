extends TextureButton
class_name CircularTextureButton

func _has_point(point: Vector2) -> bool:
	var min_side: float = min(size.x, size.y)
	if min_side <= 0.0:
		return false
	var radius: float = min_side * 0.5
	var center: Vector2 = size * 0.5
	return point.distance_to(center) <= radius
