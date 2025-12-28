extends Node
class_name NormalNeutralMobCombat

var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, owner: Node2D, target: Node2D, attack_value: int) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	if target == null or not is_instance_valid(target):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = owner.global_position.distance_to(target.global_position)
	if dist > melee_attack_range:
		return

	if _attack_timer > 0.0:
		return

	if target.has_method("take_damage"):
		target.call("take_damage", attack_value)

	_attack_timer = melee_cooldown

func get_stop_distance() -> float:
	return melee_stop_distance
