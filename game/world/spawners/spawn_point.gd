@tool
extends Node2D
class_name SpawnPoint
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

# Единая точка спавна для всех типов групп.
# guard_facing используется в режиме Guard (задел на будущее).
@export_enum("Default", "Up", "Right", "Down", "Left") var guard_facing: int = 0

# Если включено — конкретная точка всегда работает как Guard,
# даже если в группе выбран Patrol.
var _override_group_patrol_to_guard: bool = false
var _show_patrol_marker_in_game: bool = false
var _patrol_marker_color: Color = Color(0.2, 0.8, 1.0, 0.35)

@export var override_group_patrol_to_guard: bool = false:
	set(v):
		_override_group_patrol_to_guard = bool(v)
		queue_redraw()
	get:
		return _override_group_patrol_to_guard

# (на будущее) произвольный тег/вариант, если понадобится.
@export var tag: String = ""

# Показывать маркер в рантайме (в редакторе всегда показывается при условии ниже).
@export var show_patrol_marker_in_game: bool = false:
	set(v):
		_show_patrol_marker_in_game = bool(v)
		queue_redraw()
	get:
		return _show_patrol_marker_in_game

@export var patrol_marker_color: Color = Color(0.2, 0.8, 1.0, 0.35):
	set(v):
		_patrol_marker_color = v
		queue_redraw()
	get:
		return _patrol_marker_color

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint() or show_patrol_marker_in_game:
		set_process(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or show_patrol_marker_in_game:
		queue_redraw()

func resolve_effective_behavior(group_behavior: int, guard_behavior_value: int = 0) -> int:
	if override_group_patrol_to_guard:
		return guard_behavior_value
	return group_behavior

func _draw() -> void:
	if not _should_draw_patrol_marker():
		return
	var radius := COMBAT_RANGES.PATROL_RADIUS
	draw_circle(Vector2.ZERO, radius, Color(_patrol_marker_color.r, _patrol_marker_color.g, _patrol_marker_color.b, _patrol_marker_color.a * 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, _patrol_marker_color, 2.0, true)

func _should_draw_patrol_marker() -> bool:
	if not Engine.is_editor_hint() and not show_patrol_marker_in_game:
		return false
	if override_group_patrol_to_guard:
		return false
	var parent_node := get_parent()
	if parent_node == null:
		return false
	if not ("behavior" in parent_node):
		return false
	return int(parent_node.get("behavior")) == 1
