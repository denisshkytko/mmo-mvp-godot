extends Node
class_name NormalAggresiveMobCombat

enum AttackMode { MELEE, RANGED }

var attack_mode: int = AttackMode.MELEE

# melee params
var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

# ranged params
var ranged_attack_range: float = 220.0
var ranged_cooldown: float = 1.5
var ranged_projectile_scene: PackedScene = null

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, owner: Node2D, player: Node2D, attack_value: int) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("take_damage"):
		return

	var dist: float = owner.global_position.distance_to(player.global_position)

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _attack_timer <= 0.0:
			player.call("take_damage", attack_value)
			_attack_timer = melee_cooldown
	else:
		if dist <= ranged_attack_range and _attack_timer <= 0.0:
			# пока instant-hit (снаряд подключим позже, когда решишь)
			player.call("take_damage", attack_value)
			_attack_timer = ranged_cooldown

func get_stop_distance() -> float:
	if attack_mode == AttackMode.MELEE:
		return melee_stop_distance
	return ranged_attack_range
