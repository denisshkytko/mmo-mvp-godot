extends Node
class_name PlayerCombat

var p: Player = null
var _attack_timer: float = 0.0

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if p == null:
		return

	_attack_timer = max(0.0, _attack_timer - delta)

	# автоатака только если есть таргет и цель в range
	if _attack_timer > 0.0:
		return

	var target: Node2D = _get_current_target()
	if target == null:
		return

	var dist: float = p.global_position.distance_to(target.global_position)
	if dist > p.attack_range:
		return

	_apply_damage_to_target(target, get_attack_damage())
	_attack_timer = p.attack_cooldown

func get_attack_damage() -> int:
	var buffs: PlayerBuffs = p.c_buffs
	var bonus: int = 0
	if buffs != null:
		bonus = buffs.get_attack_bonus_total()
	return p.attack + bonus

func _apply_damage_to_target(target: Node2D, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.call("take_damage", dmg)

func _get_current_target() -> Node2D:
	var gm: Node = p.get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.has_method("get_target"):
		return null

	var t = gm.call("get_target")
	if t != null and t is Node2D and is_instance_valid(t):
		return t as Node2D
	return null
