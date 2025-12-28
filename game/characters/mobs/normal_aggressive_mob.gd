extends CharacterBody2D
class_name NormalAggresiveMob

signal died(corpse: Corpse)

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@onready var c_ai: NormalAggresiveMobAI = $Components/AI as NormalAggresiveMobAI
@onready var c_combat: NormalAggresiveMobCombat = $Components/Combat as NormalAggresiveMobCombat
@onready var c_stats: NormalAggresiveMobStats = $Components/Stats as NormalAggresiveMobStats

enum AttackMode { MELEE, RANGED }

# ------------------------------------------------------------
# ДЕФОЛТЫ "на всякий случай" (могут переопределяться спавнером)
# ------------------------------------------------------------
@export_group("Common Defaults (optional)")
@export var aggro_radius: float = 260.0
@export var base_xp: int = 5
@export var xp_per_level: int = 2

# Эти поля выставляет спавнер
var mob_id: String = "slime"
var loot_table_id: String = "lt_slime_low"
var mob_level: int = 1
var attack_mode: int = AttackMode.MELEE

var home_position: Vector2 = Vector2.ZERO

# Стандартная сцена трупа (для всех мобов)
const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

# Награда опыта
var xp_reward: int = 0

var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.02
# ------------------------------------------------------------
# Параметры двух состояний (без dropdown-скрытия)
# ------------------------------------------------------------
@export_group("Melee Mode")
@export var melee_base_attack: int = 8
@export var melee_attack_per_level: int = 2
@export var melee_base_max_hp: int = 50
@export var melee_base_defense: int = 1
@export var melee_defense_per_level: int = 1
@export var melee_stop_distance: float = 45.0
@export var melee_attack_range: float = 55.0
@export var melee_attack_cooldown: float = 1.2

@export_group("Ranged Mode")
@export var ranged_base_attack: int = 7
@export var ranged_attack_per_level: int = 2
@export var ranged_base_max_hp: int = 44
@export var ranged_base_defense: int = 1
@export var ranged_defense_per_level: int = 1
@export var ranged_attack_range: float = 220.0
@export var ranged_attack_cooldown: float = 1.5
@export var ranged_projectile_scene: PackedScene = null # пока instant-hit

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var player: Node2D = null

var faction_id: String = "aggressive_mob"
var current_target: Node2D = null

var first_attacker: Node2D = null
var last_attacker: Node2D = null

var loot_owner_player_id: int = 0


func _ready() -> void:
	add_to_group("faction_units")
	player = get_tree().get_first_node_in_group("player") as Node2D

	if c_ai != null and c_ai.has_signal("leash_return_started"):
		var cb := Callable(self, "_on_leash_return_started")
		if not c_ai.leash_return_started.is_connected(cb):
			c_ai.leash_return_started.connect(cb)

	if home_position == Vector2.ZERO:
		home_position = global_position

	_apply_mode_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.update_hp_bar(hp_fill)

func _process(_delta: float) -> void:
	if target_marker == null:
		return

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var is_target: bool = false
	if gm != null and gm.has_method("get_target"):
		is_target = (gm.call("get_target") == self)

	target_marker.visible = is_target

func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

	if current_target == null or not is_instance_valid(current_target):
		current_target = _pick_target()
	else:
		# если цель стала не-hostile — сбрасываем
		var tf := ""
		if current_target.has_method("get_faction_id"):
			tf = String(current_target.call("get_faction_id"))
		if FactionRules.relation(faction_id, tf) != FactionRules.Relation.HOSTILE:
			current_target = null

	# реген после leash-return, продолжается даже в idle/patrol пока не станет full hp
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		var heal_amount: int = int(round(float(c_stats.max_hp) * REGEN_PCT_PER_SEC * delta))
		if heal_amount <= 0:
			heal_amount = 1
		c_stats.current_hp = min(c_stats.max_hp, c_stats.current_hp + heal_amount)
		c_stats.update_hp_bar(hp_fill)
	elif regen_active and c_stats.current_hp >= c_stats.max_hp:
		regen_active = false

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_apply_mode_to_components()

	c_ai.tick(delta, self, current_target, c_combat)

	if current_target != null and is_instance_valid(current_target):
		c_combat.tick(delta, self, current_target, c_stats.attack_value)

# ------------------------------------------------------------
# Called by Spawner
# ------------------------------------------------------------
func apply_spawn_init(
	spawn_pos: Vector2,
	behavior_in: int,
	aggro_radius_in: float,
	leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	speed_in: float,
	level_in: int,
	attack_mode_in: int,
	mob_id_in: String,
	loot_table_id_in: String
) -> void:
	# Эти поля должны выставляться до расчётов/AI

	# ⚠️ ВАЖНО:
	# NamSpawnerGroup передаёт mob_id_in = ""
	# поэтому НЕ затираем mob_id, если пришло пустое значение
	if mob_id_in != "":
		mob_id = mob_id_in

	loot_table_id = loot_table_id_in

	apply_spawn_settings(
		spawn_pos,
		behavior_in,
		aggro_radius_in,
		leash_distance_in,
		patrol_radius_in,
		patrol_pause_in,
		speed_in
	)

	# уровень/режим атаки выставляем как было
	set_level(level_in)
	attack_mode = attack_mode_in


func apply_spawn_settings(
	spawn_pos: Vector2,
	behavior_in: int,
	aggro_radius_in: float,
	leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	speed_in: float
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	if c_ai != null:
		c_ai.behavior = behavior_in
		c_ai.aggro_radius = aggro_radius_in
		c_ai.leash_distance = leash_distance_in
		c_ai.patrol_radius = patrol_radius_in
		c_ai.patrol_pause_seconds = patrol_pause_in
		c_ai.speed = speed_in
		c_ai.home_position = home_position
		c_ai.reset_to_idle()


func set_attack_mode(mode: int) -> void:
	attack_mode = mode
	_apply_mode_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.update_hp_bar(hp_fill)

func set_level(level: int) -> void:
	mob_level = max(1, level)
	c_stats.recalculate_for_level(mob_level)
	c_stats.update_hp_bar(hp_fill)

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
func take_damage(raw_damage: int) -> void:
	take_damage_from(raw_damage, null)

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	if c_stats.is_dead:
		return

	_set_loot_owner_if_first(attacker)

	if first_attacker == null and attacker != null and is_instance_valid(attacker):
		first_attacker = attacker
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker

	var died_now: bool = c_stats.apply_damage(raw_damage)
	c_stats.update_hp_bar(hp_fill)

	if died_now:
		_die()


func on_player_died() -> void:
	_clear_loot_owner()
	c_combat.reset_combat()
	c_ai.force_return()
	velocity = Vector2.ZERO

# ------------------------------------------------------------
# Internals
# ------------------------------------------------------------
func _apply_mode_to_components() -> void:
	c_ai.home_position = home_position

	# Если спавнер ещё не применил настройки — используем дефолтный aggro_radius
	# (только если AI сейчас с "пустым" значением)
	if c_ai.aggro_radius <= 0.0:
		c_ai.aggro_radius = aggro_radius

	# combat
	c_combat.attack_mode = attack_mode

	c_combat.melee_stop_distance = melee_stop_distance
	c_combat.melee_attack_range = melee_attack_range
	c_combat.melee_cooldown = melee_attack_cooldown

	c_combat.ranged_attack_range = ranged_attack_range
	c_combat.ranged_cooldown = ranged_attack_cooldown
	c_combat.ranged_projectile_scene = ranged_projectile_scene

	c_stats.mob_level = mob_level

	if attack_mode == AttackMode.MELEE:
		c_stats.base_attack = melee_base_attack
		c_stats.attack_per_level = melee_attack_per_level
		c_stats.base_max_hp = melee_base_max_hp
		c_stats.base_defense = melee_base_defense
		c_stats.defense_per_level = melee_defense_per_level
	else:
		c_stats.base_attack = ranged_base_attack
		c_stats.attack_per_level = ranged_attack_per_level
		c_stats.base_max_hp = ranged_base_max_hp
		c_stats.base_defense = ranged_base_defense
		c_stats.defense_per_level = ranged_defense_per_level

func _die() -> void:
	if c_stats.is_dead:
		return
	c_stats.is_dead = true


	var corpse: Corpse = null
	var inst := CORPSE_SCENE.instantiate()
	corpse = inst as Corpse
	if corpse != null:
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		if corpse != null and corpse.has_method("set_loot_owner_player"):
			var owner_player: Node = get_tree().get_first_node_in_group("player")
			# owner только если текущий id совпадает с игроком
			if owner_player != null and owner_player.get_instance_id() == loot_owner_player_id:
				corpse.call("set_loot_owner_player", owner_player)
			else:
				corpse.call("set_loot_owner_player", null)


		var table_id: String = loot_table_id
		if table_id == "":
			table_id = "lt_slime_low"

		var loot: Dictionary = LootSystem.generate_loot(table_id, mob_level)
		if corpse.has_method("set_loot_v2"):
			corpse.call("set_loot_v2", loot)
		else:
			corpse.loot_gold = int(loot.get("gold", 0))

	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("add_xp"):
		p.add_xp(_get_xp_reward())

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self:
			gm.call("clear_target")

	emit_signal("died", corpse)
	queue_free()

func _get_xp_reward() -> int:
	if xp_reward > 0:
		return xp_reward

	return base_xp + mob_level * xp_per_level


func _on_leash_return_started() -> void:
	# бой сбросился → права на лут больше нет
	_clear_loot_owner()
	regen_active = true


func get_faction_id() -> String:
	return faction_id


func _pick_target() -> Node2D:
	# выбираем ближайшую враждебную цель в агро-радиусе
	var best: Node2D = null
	var best_d := INF

	var units := get_tree().get_nodes_in_group("faction_units")
	for u in units:
		if u == self:
			continue
		if not (u is Node2D):
			continue
		var n := u as Node2D
		if not is_instance_valid(n):
			continue
		if "is_dead" in n and bool(n.get("is_dead")):
			continue

		# faction check
		var tf := ""
		if n.has_method("get_faction_id"):
			tf = String(n.call("get_faction_id"))
		var rel := FactionRules.relation(faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue

		var d := global_position.distance_to(n.global_position)
		if d <= aggro_radius and d < best_d:
			best_d = d
			best = n

	return best


func _set_loot_owner_if_first(attacker: Node2D) -> void:
	if loot_owner_player_id != 0:
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	if not attacker.is_in_group("player"):
		return
	loot_owner_player_id = attacker.get_instance_id()


func _clear_loot_owner() -> void:
	loot_owner_player_id = 0
