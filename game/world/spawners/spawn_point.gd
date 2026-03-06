extends Node2D
class_name SpawnPoint

const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

# Единая точка спавна для всех типов групп.
# guard_facing используется в режиме Guard (задел на будущее).
@export_enum("Default", "Up", "Right", "Down", "Left") var guard_facing: int = 0

# (на будущее) произвольный тег/вариант, если понадобится.
@export var tag: String = ""


func _process(_delta: float) -> void:
	if OS.is_debug_build():
		queue_redraw()


func _draw() -> void:
	if not OS.is_debug_build():
		return
	var parent := get_parent()
	if parent == null:
		return
	var patrol_radius: float = COMBAT_RANGES.PATROL_RADIUS
	if "patrol_radius" in parent:
		patrol_radius = float(parent.get("patrol_radius"))
	if patrol_radius <= 0.0:
		return
	draw_arc(Vector2.ZERO, patrol_radius, 0.0, TAU, 96, Color(0.2, 0.6, 1.0, 0.85), 1.5, true)
