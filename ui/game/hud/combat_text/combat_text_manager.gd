extends Node2D
class_name CombatTextManager

const FLOATING_DAMAGE_NUMBER_SCENE := preload("res://ui/game/hud/combat_text/floating_damage_number.tscn")

const PHYSICAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const MAGIC_COLOR := Color(0.98, 0.86, 0.28, 1.0)
const HEAL_COLOR := Color(0.42, 1.0, 0.45, 1.0)
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BASE_Y_OFFSET := -30.0
const SIDE_OFFSET_STEP := 22.0
const BURST_WINDOW_MS := 160

var _burst_state: Dictionary = {}

func show_damage(target: Node2D, final_damage: int, dmg_type: String) -> void:
	_show_value(target, final_damage, dmg_type)

func show_heal(target: Node2D, heal_amount: int) -> void:
	_show_value(target, heal_amount, "heal")

func _show_value(target: Node2D, value: int, value_type: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if value <= 0:
		return
	if FLOATING_DAMAGE_NUMBER_SCENE == null:
		return

	var instance: FloatingDamageNumber = FLOATING_DAMAGE_NUMBER_SCENE.instantiate() as FloatingDamageNumber
	if instance == null:
		return

	var burst_index: int = _next_burst_index(target)
	var start: Vector2 = _resolve_start_position(target, burst_index)
	instance.position = start
	add_child(instance)
	instance.show_value(value, _color_for_value_type(value_type))

func _resolve_start_position(target: Node2D, burst_index: int) -> Vector2:
	var x_offset: float = _burst_side_offset(burst_index)
	return target.global_position + Vector2(x_offset, BASE_Y_OFFSET)

func _burst_side_offset(index: int) -> float:
	if index == 0:
		return -SIDE_OFFSET_STEP
	if index == 1:
		return SIDE_OFFSET_STEP
	var pair: int = int(floor(float(index - 2) / 2.0))
	var magnitude: float = SIDE_OFFSET_STEP * float(pair + 2)
	return -magnitude if index % 2 == 0 else magnitude

func _next_burst_index(target: Node2D) -> int:
	var key: int = target.get_instance_id()
	var now_ms: int = Time.get_ticks_msec()
	var entry: Dictionary = _burst_state.get(key, {}) as Dictionary
	var last_ms: int = int(entry.get("time", 0))
	var next_index: int = 0
	if now_ms - last_ms <= BURST_WINDOW_MS:
		next_index = int(entry.get("index", -1)) + 1
	_burst_state[key] = {
		"time": now_ms,
		"index": next_index,
	}
	return next_index

func _color_for_value_type(value_type: String) -> Color:
	if value_type == "physical":
		return PHYSICAL_COLOR
	if value_type == "magic":
		return MAGIC_COLOR
	if value_type == "heal":
		return HEAL_COLOR
	return DEFAULT_COLOR
