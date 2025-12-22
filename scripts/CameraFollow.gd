extends Camera2D

@export var world_left: float = -1000.0
@export var world_right: float = 1000.0
@export var world_top: float = -600.0
@export var world_bottom: float = 600.0

func _ready() -> void:
	# ждём 1 кадр, чтобы viewport size был корректным
	await get_tree().process_frame
	_apply_limits()

	# пересчитываем, если меняется размер окна
	get_viewport().size_changed.connect(func():
		_apply_limits()
	)

func _apply_limits() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var half_w: float = (vp.x * 0.5) / zoom.x
	var half_h: float = (vp.y * 0.5) / zoom.y

	# лимиты для ЦЕНТРА камеры так, чтобы края экрана не выходили за мир
	limit_left = int(world_left + half_w)
	limit_right = int(world_right - half_w)
	limit_top = int(world_top + half_h)
	limit_bottom = int(world_bottom - half_h)

	# если мир меньше экрана — фиксируем камеру по центру мира
	if limit_left > limit_right:
		var mid_x := int((world_left + world_right) * 0.5)
		limit_left = mid_x
		limit_right = mid_x
	if limit_top > limit_bottom:
		var mid_y := int((world_top + world_bottom) * 0.5)
		limit_top = mid_y
		limit_bottom = mid_y
