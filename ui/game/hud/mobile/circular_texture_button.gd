extends TextureButton
class_name CircularTextureButton

func _has_point(point: Vector2) -> bool:
	var min_side := min(size.x, size.y)
	if min_side <= 0.0:
		return false
	var radius := min_side * 0.5
	var center := size * 0.5
	return point.distance_to(center) <= radius
