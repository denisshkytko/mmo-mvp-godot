extends CharacterBody2D
class_name Mob

signal died(corpse: Corpse)

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

# -----------------------------
# Enums
# -----------------------------
enum Behavior { GUARD, PATROL }
enum AIState { IDLE, CHASE, RETURN }

# -----------------------------
# Movement / AI params (set by spawner)
# -----------------------------
var behavior: int = Behavior.GUARD
var speed: float = 120.0
var aggro_radius: float = 260.0
var stop_distance: float = 45.0
var leash_distance: float = 420.0

# Patrol
var patrol_radius: float = 140.0
var patrol_pause_seconds: float = 1.5

# -----------------------------
# Home / patrol internals
# -----------------------------
var home_position: Vector2
var _patrol_target: Vector2
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0

# RETURN → re-aggro if damaged
var _force_chase_timer: float = 0.0
var force_chase_seconds: float = 0.6

# -----------------------------
# Combat / Stats
# -----------------------------
@export var mob_level: int = 1
@export var mob_attack_cooldown: float = 1.2
@export var base_attack: int = 8
@export var attack_per_level: int = 2

@export var base_max_hp: int = 50
@export var hp_per_level: int = 12
@export var base_defense: int = 1
@export var defense_per_level: int = 1
@export var strength_multiplier: float = 0.9

@export var corpse_scene: PackedScene
@export var xp_reward: int = 0

var loot_table_id: String = ""
var mob_id: String = "slime"

var max_hp: int = 50
var current_hp: int = 50
var defense: int = 1
var attack: int = 8

var player: Node2D = null
var _attack_timer: float = 0.0

var _state: int = AIState.IDLE
var _dead: bool = false


# -----------------------------
# Called by Spawner BEFORE gameplay starts
# -----------------------------
func apply_spawn_settings(
	spawn_pos: Vector2,
	behavior_in: int,
	aggro_radius_in: float,
	leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	behavior = behavior_in
	aggro_radius = aggro_radius_in
	leash_distance = leash_distance_in
	patrol_radius = patrol_radius_in
	patrol_pause_seconds = patrol_pause_in

	_has_patrol_target = false
	_patrol_wait = 0.0
	_force_chase_timer = 0.0
	_attack_timer = 0.0
	_state = AIState.IDLE


func _ready() -> void:
	_recalculate_stats_for_level()
	_update_hp_bar()

	player = get_tree().get_first_node_in_group("player") as Node2D

	# Если спавнер не вызывал apply_spawn_settings — считаем текущую позицию домом
	if home_position == Vector2.ZERO:
		home_position = global_position


func _process(_delta: float) -> void:
	if target_marker == null:
		return

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var is_target: bool = false
	if gm != null and gm.has_method("get_target"):
		is_target = (gm.call("get_target") == self)

	target_marker.visible = is_target


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Если игрок мёртв — немедленно прекращаем бой и уходим домой
	if player != null and is_instance_valid(player):
		if "is_dead" in player and bool(player.get("is_dead")):
			_attack_timer = 0.0
			_force_chase_timer = 0.0
			_state = AIState.RETURN
			velocity = Vector2.ZERO

	_attack_timer = max(0.0, _attack_timer - delta)
	_force_chase_timer = max(0.0, _force_chase_timer - delta)

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	# 1) Главное правило выключения CHASE: leash_distance
	var dist_to_home: float = global_position.distance_to(home_position)
	if _state == AIState.CHASE and dist_to_home > leash_distance:
		_state = AIState.RETURN

	# 2) RETURN
	if _state == AIState.RETURN:
		_do_return(delta)
		return

	# 3) Включаем CHASE, только когда игрок впервые вошёл в агро-радиус
	if _state != AIState.CHASE:
		if player != null and is_instance_valid(player):
			var dist_to_player: float = global_position.distance_to(player.global_position)
			if dist_to_player <= aggro_radius:
				_state = AIState.CHASE

	# 4) CHASE (НЕ выключается от выхода игрока из агро-радиуса)
	if _state == AIState.CHASE:
		_do_chase(delta)
		return

	# 5) IDLE
	_do_idle(delta)


func _do_idle(delta: float) -> void:
	if behavior == Behavior.PATROL:
		_do_patrol(delta)
	else:
		velocity = Vector2.ZERO
		move_and_slide()


func _pick_new_patrol_target() -> void:
	_has_patrol_target = true
	var min_r: float = max(10.0, patrol_radius * 0.30)
	var angle: float = randf() * TAU
	var r: float = lerp(min_r, patrol_radius, randf())
	_patrol_target = home_position + Vector2(cos(angle), sin(angle)) * r


func _do_patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not _has_patrol_target:
		_pick_new_patrol_target()

	var d: float = global_position.distance_to(_patrol_target)
	if d <= 6.0:
		_patrol_wait = patrol_pause_seconds
		_pick_new_patrol_target()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	velocity = (_patrol_target - global_position).normalized() * speed
	move_and_slide()


func _do_chase(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_state = AIState.IDLE
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	if dist > stop_distance:
		velocity = to_player.normalized() * speed
		move_and_slide()
		return

	velocity = Vector2.ZERO
	move_and_slide()

	if _attack_timer <= 0.0 and player.has_method("take_damage"):
		player.call("take_damage", attack)
		_attack_timer = mob_attack_cooldown


func _do_return(delta: float) -> void:
	# Если во время RETURN получили урон и всё ещё в leash — снова CHASE
	if _force_chase_timer > 0.0 and player != null and is_instance_valid(player):
		var dist_home: float = global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_state = AIState.CHASE
			return

	# реген 5%/сек
	var regen: int = int(round(float(max_hp) * 0.05 * delta))
	if regen > 0:
		current_hp = min(max_hp, current_hp + regen)
		_update_hp_bar()

	var to_home: Vector2 = home_position - global_position
	var dist: float = to_home.length()

	if dist <= 6.0:
		_state = AIState.IDLE
		_has_patrol_target = false
		_patrol_wait = patrol_pause_seconds
		velocity = Vector2.ZERO
		move_and_slide()
		return

	velocity = to_home.normalized() * speed
	move_and_slide()


func _recalculate_stats_for_level() -> void:
	max_hp = int(round((base_max_hp + (mob_level - 1) * hp_per_level) * strength_multiplier))
	defense = int(round((base_defense + (mob_level - 1) * defense_per_level) * strength_multiplier))
	attack = int(round((base_attack + (mob_level - 1) * attack_per_level) * strength_multiplier))

	if max_hp < 10:
		max_hp = 10
	if defense < 1:
		defense = 1
	if attack < 1:
		attack = 1

	current_hp = max_hp


func take_damage(raw_damage: int) -> void:
	if _dead:
		return

	var dmg: int = max(1, raw_damage - defense)
	current_hp = max(0, current_hp - dmg)
	_update_hp_bar()

	# Ре-агр во время RETURN, но только если всё ещё в leash
	if _state == AIState.RETURN:
		var dist_home: float = global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_force_chase_timer = force_chase_seconds
			_state = AIState.CHASE
	else:
		_state = AIState.CHASE

	if current_hp <= 0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true

	# 1) Spawn corpse
	var corpse: Corpse = null
	if corpse_scene != null:
		var inst := corpse_scene.instantiate()
		corpse = inst as Corpse
		if corpse != null:
			get_parent().add_child(corpse)
			corpse.global_position = global_position

			# Data-driven loot
			var table_id := loot_table_id
			if table_id == "":
				table_id = "lt_slime_low"

			var loot: Dictionary = LootSystem.generate_loot(table_id, mob_level)
			if corpse.has_method("set_loot_v2"):
				corpse.call("set_loot_v2", loot)
			else:
				# fallback на старый формат (если ещё не обновил corpse.gd)
				corpse.loot_gold = int(loot.get("gold", 0))

	# 2) Give XP
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("add_xp"):
		p.add_xp(_get_xp_reward())

	# 3) Clear target if selected
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self:
			gm.call("clear_target")

	# 4) Notify spawner
	emit_signal("died", corpse)

	# 5) Remove mob
	queue_free()


func _get_xp_reward() -> int:
	if xp_reward > 0:
		return xp_reward
	return 2 + mob_level


func _update_hp_bar() -> void:
	if hp_fill == null:
		return
	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio


func on_player_died() -> void:
	# Сразу прекращаем бой и возвращаемся домой
	_attack_timer = 0.0
	_force_chase_timer = 0.0
	_state = AIState.RETURN
	velocity = Vector2.ZERO
