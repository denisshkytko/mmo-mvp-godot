extends TextureButton
class_name CircularTextureButton

func _has_point(point: Vector2) -> bool:
	var min_side: float = min(size.x, size.y)
	if min_side <= 0.0:
		return false
	var radius: float = min_side * 0.5
	var center: Vector2 = size * 0.5
	return point.distance_to(center) <= radius


const CIRCLE_MASK_SHADER := preload("res://ui/game/hud/mobile/circle_mask.gdshader")

func _ready() -> void:
	clip_children = Control.CLIP_CHILDREN_AND_DRAW
	for child in get_children():
		if child is TextureRect:
			_apply_circle_mask(child as TextureRect)

func _apply_circle_mask(icon_rect: TextureRect) -> void:
	if icon_rect == null:
		return
	if CIRCLE_MASK_SHADER == null:
		return
	var material := ShaderMaterial.new()
	material.shader = CIRCLE_MASK_SHADER
	icon_rect.material = material
