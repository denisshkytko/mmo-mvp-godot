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

	# если игрок мёртв — не атакуем
	if "is_dead" in player and bool(player.get("is_dead")):
		return

	var dist: float = owner.global_position.distance_to(player.global_position)

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _attack_timer <= 0.0:
			player.call("take_damage", attack_value)
			_attack_timer = melee_cooldown
		return

	# RANGED
	if dist <= ranged_attack_range and _attack_timer <= 0.0:
		_fire_ranged(owner, player, attack_value)
		_attack_timer = ranged_cooldown

func _fire_ranged(owner: Node2D, player: Node2D, damage: int) -> void:
	# Если сцена не назначена — fallback на instant-hit (чтобы не сломать игру)
	if ranged_projectile_scene == null:
		player.call("take_damage", damage)
		return

	var inst := ranged_projectile_scene.instantiate()
	var proj := inst as Node2D
	if proj == null:
		# если кто-то случайно назначил не Node2D
		player.call("take_damage", damage)
		return

	# добавляем в мир рядом с мобом (на уровень выше моба)
	var parent := owner.get_parent()
	if parent == null:
		player.call("take_damage", damage)
		return

	parent.add_child(proj)
	proj.global_position = owner.global_position

	# setup если есть метод
	if proj.has_method("setup"):
		proj.call("setup", player, damage, owner)

func get_stop_distance() -> float:
	if attack_mode == AttackMode.MELEE:
		return melee_stop_distance
	return ranged_attack_range
