extends Node2D
class_name CombatTextManager

const FLOATING_DAMAGE_NUMBER_SCENE := preload("res://ui/game/hud/combat_text/floating_damage_number.tscn")

const PHYSICAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const MAGIC_COLOR := Color(0.98, 0.86, 0.28, 1.0)
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BASE_Y_OFFSET := -30.0
const SIDE_OFFSET_STEP := 14.0
const BURST_WINDOW_MS := 160

var _burst_state: Dictionary = {}

func show_damage(target: Node2D, final_damage: int, dmg_type: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if final_damage <= 0:
		return
	if FLOATING_DAMAGE_NUMBER_SCENE == null:
		return

	var instance := FLOATING_DAMAGE_NUMBER_SCENE.instantiate() as FloatingDamageNumber
	if instance == null:
		return

	var burst_index := _next_burst_index(target)
	var start := _resolve_start_position(target, burst_index)
	instance.position = start
	add_child(instance)
	instance.show_value(final_damage, _color_for_damage_type(dmg_type))

func _resolve_start_position(target: Node2D, burst_index: int) -> Vector2:
	var x_offset := _burst_side_offset(burst_index)
	return target.global_position + Vector2(x_offset, BASE_Y_OFFSET)

func _burst_side_offset(index: int) -> float:
	if index <= 0:
		return -SIDE_OFFSET_STEP * 0.5
	var pair := int(floor(float(index) / 2.0))
	var magnitude := SIDE_OFFSET_STEP * float(pair + 1)
	return -magnitude if index % 2 == 0 else magnitude

func _next_burst_index(target: Node2D) -> int:
	var key := target.get_instance_id()
	var now_ms := Time.get_ticks_msec()
	var entry: Dictionary = _burst_state.get(key, {}) as Dictionary
	var last_ms := int(entry.get("time", 0))
	var next_index := 0
	if now_ms - last_ms <= BURST_WINDOW_MS:
		next_index = int(entry.get("index", -1)) + 1
	_burst_state[key] = {
		"time": now_ms,
		"index": next_index,
	}
	return next_index

func _color_for_damage_type(dmg_type: String) -> Color:
	if dmg_type == "physical":
		return PHYSICAL_COLOR
	if dmg_type == "magic":
		return MAGIC_COLOR
	return DEFAULT_COLOR
