extends CharacterBody2D
class_name NormalAggresiveMob

## These helpers are registered as global classes (class_name).
## Avoid shadowing them with local constants.
const MOB_VARIANT := preload("res://core/stats/mob_variant.gd")
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")

signal died(corpse: Corpse)

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@onready var c_ai: NormalAggresiveMobAI = $Components/AI as NormalAggresiveMobAI
@onready var c_combat: NormalAggresiveMobCombat = $Components/Combat as NormalAggresiveMobCombat
@onready var c_stats: NormalAggresiveMobStats = $Components/Stats as NormalAggresiveMobStats
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent
@onready var c_danger: DangerMeterComponent = $Components/Danger as DangerMeterComponent

enum AttackMode { MELEE, RANGED }

# ------------------------------------------------------------
# ДЕФОЛТЫ "на всякий случай" (могут переопределяться спавнером)
# ------------------------------------------------------------
@export_group("Common")
@export var base_xp: int = 5
@export var xp_per_level: int = 2
@export var move_speed: float = MOVE_SPEED.MOB_BASE
@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0

# Эти поля выставляет спавнер
var mob_id: String = "slime"
var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_aggressive_default.tres") as LootProfile
var mob_level: int = 1
var attack_mode: int = AttackMode.MELEE
var mob_variant: int = MOB_VARIANT.MobVariant.NORMAL
var abilities: Array[String] = []

var home_position: Vector2 = Vector2.ZERO

# Стандартная сцена трупа (для всех мобов)
const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")
const BASE_XP_L1_AGGRESSIVE: int = 10

# Награда опыта
var xp_reward: int = 0

var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.02
var _spawn_initialized: bool = false
# ------------------------------------------------------------
# Параметры двух состояний (без dropdown-скрытия)
# ------------------------------------------------------------
@export_group("Характеристики: Aggressive Mob (Melee)")
@export_subgroup("Базовые характеристики")
@export var melee_base_str: int = 11
@export var melee_base_agi: int = 0
@export var melee_base_end: int = 4
@export var melee_base_int: int = 0
@export var melee_base_per: int = 0
@export var melee_base_defense: int = 1
@export var melee_defense_per_level: int = 1
@export var melee_base_magic_resist: int = 0
@export var melee_magic_resist_per_level: int = 0
@export var melee_stop_distance: float = 45.0
@export var melee_attack_range: float = 55.0
@export var melee_attack_cooldown: float = 1.2

@export_subgroup("Рост базовых характеристик")
@export var melee_str_per_level: int = 3
@export var melee_agi_per_level: int = 0
@export var melee_end_per_level: int = 1
@export var melee_int_per_level: int = 0
@export var melee_per_per_level: int = 0

@export_group("Характеристики: Aggressive Mob (Ranged)")
@export_subgroup("Базовые характеристики")
@export var ranged_base_str: int = 10
@export var ranged_base_agi: int = 2
@export var ranged_base_end: int = 3
@export var ranged_base_int: int = 0
@export var ranged_base_per: int = 1
@export var ranged_base_defense: int = 1
@export var ranged_defense_per_level: int = 1
@export var ranged_base_magic_resist: int = 0
@export var ranged_magic_resist_per_level: int = 0
@export var ranged_attack_range: float = 220.0
@export var ranged_attack_cooldown: float = 1.5
@export var ranged_projectile_scene: PackedScene = null

@export_subgroup("Рост базовых характеристик")
@export var ranged_str_per_level: int = 3
@export var ranged_agi_per_level: int = 0
@export var ranged_end_per_level: int = 1
@export var ranged_int_per_level: int = 0
@export var ranged_per_per_level: int = 0

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
var player: Node2D = null



var faction_id: String = "aggressive_mob"
var current_target: Node2D = null
var _prev_target: Node2D = null
var direct_attackers := {} # instance_id -> last_hit_time_sec

var first_attacker: Node2D = null
var last_attacker: Node2D = null

var loot_owner_player_id: int = 0

const THREAT_RECHECK_SEC: float = 0.25
var _threat_recheck_timer: float = 0.0


func _ready() -> void:
	add_to_group("faction_units")
	player = NodeCache.get_player(get_tree()) as Node2D

	if c_ai != null and c_ai.has_signal("leash_return_started"):
		var cb := Callable(self, "_on_leash_return_started")
		if not c_ai.leash_return_started.is_connected(cb):
			c_ai.leash_return_started.connect(cb)

	if home_position == Vector2.ZERO:
		home_position = global_position

	# If the mob is placed manually in the scene, apply Common params to AI.
	if c_ai != null:
		c_ai.home_position = home_position
		c_ai.aggro_radius = aggro_radius
		c_ai.leash_distance = leash_distance
		c_ai.speed = move_speed

	_apply_mode_to_components()
	# Пересчёт в _ready нужен только если моб размещён вручную в сцене.
	# Для мобов из спавнера пересчёт выполняется в apply_spawn_init/set_level.
	if not _spawn_initialized:
		_setup_resource_from_class(c_stats.class_id if c_stats != null else "")
		c_stats.recalculate_for_level(mob_level)
		c_stats.update_hp_bar(hp_fill)

func _process(_delta: float) -> void:
	# TargetMarker показывает тех, кто сейчас агрессирует на игрока.
	var is_aggro_on_player: bool = false
	if current_target != null and is_instance_valid(current_target):
		is_aggro_on_player = current_target.is_in_group("player")
	TargetMarkerHelper.set_marker_visible(target_marker, is_aggro_on_player)

func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

	_threat_recheck_timer = max(0.0, _threat_recheck_timer - delta)

	if current_target == null or not is_instance_valid(current_target):
		current_target = _pick_target()
	else:
		if "is_dead" in current_target and bool(current_target.get("is_dead")):
			current_target = null
			regen_active = true
		else:
			# если цель стала не-hostile — сбрасываем
			var tf := ""
			if current_target.has_method("get_faction_id"):
				tf = String(current_target.call("get_faction_id"))
			if FactionRules.relation(faction_id, tf) != FactionRules.Relation.HOSTILE:
				current_target = null
	if current_target != null and c_ai != null and c_ai.is_returning():
		current_target = null
		regen_active = true
	if current_target == null and c_ai != null and not c_ai.is_returning():
		_clear_direct_attackers()

	if _prev_target != null and not is_instance_valid(_prev_target):
		_prev_target = null
	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	_refresh_threat_target()

	if _prev_target != current_target:
		var prev_valid := (_prev_target != null and is_instance_valid(_prev_target))
		var cur_valid := (current_target != null and is_instance_valid(current_target))
		if cur_valid:
			regen_active = false
		elif prev_valid and not cur_valid:
			regen_active = true
		_notify_target_change(_prev_target, current_target)
		_prev_target = current_target

	# реген после leash-return, продолжается пока HP не станет full
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		c_stats.current_hp = RegenHelper.tick_regen(c_stats.current_hp, c_stats.max_hp, delta, REGEN_PCT_PER_SEC)
		c_stats.update_hp_bar(hp_fill)
		if c_stats.current_hp >= c_stats.max_hp:
			regen_active = false

	if player == null or not is_instance_valid(player):
		player = NodeCache.get_player(get_tree()) as Node2D

	_apply_mode_to_components()

	c_ai.tick(delta, self, current_target, c_combat)

	if current_target != null and is_instance_valid(current_target):
		var snap: Dictionary = c_stats.get_stats_snapshot()
		c_combat.tick(delta, self, current_target, snap)

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
	mob_id_in: String,
	loot_profile_in: LootProfile = null,
	class_id_in: String = "",
	growth_profile_id_in: String = "",
	mob_variant_in: int = MOB_VARIANT.MobVariant.NORMAL,
	abilities_in: Array[String] = []
) -> void:
	# Эти поля должны выставляться до расчётов/AI

	# ⚠️ ВАЖНО:
	# NamSpawnerGroup передаёт mob_id_in = ""
	# поэтому НЕ затираем mob_id, если пришло пустое значение
	if mob_id_in != "":
		mob_id = mob_id_in

	if loot_profile_in != null:
		loot_profile = loot_profile_in
	abilities = abilities_in.duplicate()

	apply_spawn_settings(
		spawn_pos,
		behavior_in,
		aggro_radius_in,
		leash_distance_in,
		patrol_radius_in,
		patrol_pause_in,
		speed_in
	)

	if c_stats != null:
		c_stats.class_id = class_id_in
		c_stats.growth_profile_id = growth_profile_id_in
		c_stats.mob_variant = MOB_VARIANT.clamp_variant(mob_variant_in)
	_setup_resource_from_class(class_id_in)

	var role := Progression.get_attack_role_for_class(class_id_in)
	var chosen_mode := AttackMode.MELEE
	match role:
		"ranged":
			chosen_mode = AttackMode.RANGED
		"hybrid":
			chosen_mode = AttackMode.RANGED if randi() % 2 == 0 else AttackMode.MELEE

	attack_mode = chosen_mode
	if c_combat != null:
		var base_melee := Progression.get_base_melee_attack_interval_for_class(class_id_in)
		var base_ranged := Progression.get_npc_base_ranged_attack_interval_for_class(class_id_in)
		c_combat.melee_cooldown = base_melee
		if chosen_mode == AttackMode.RANGED:
			c_combat.ranged_cooldown = base_ranged
		c_combat.attack_mode = chosen_mode

	mob_variant = MOB_VARIANT.clamp_variant(mob_variant_in)

	# уровень/режим атаки выставляем как было
	set_level(level_in)
	_spawn_initialized = true


func _mark_spawned() -> void:
	_spawn_initialized = true


func apply_spawn_settings(
	spawn_pos: Vector2,
	behavior_in: int,
	_aggro_radius_in: float,
	_leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	_speed_in: float
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	if c_ai != null:
		c_ai.behavior = behavior_in
		# Common params are defined on the mob itself (Inspector: Common)
		c_ai.aggro_radius = aggro_radius
		c_ai.leash_distance = leash_distance
		c_ai.patrol_radius = patrol_radius_in
		c_ai.patrol_pause_seconds = patrol_pause_in
		c_ai.speed = move_speed

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

	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

	if first_attacker == null and attacker != null and is_instance_valid(attacker):
		first_attacker = attacker
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
		direct_attackers[attacker.get_instance_id()] = _now_sec()
		if c_ai != null:
			c_ai.on_took_damage(attacker)

	var died_now: bool = c_stats.apply_damage(raw_damage)
	c_stats.update_hp_bar(hp_fill)
	if c_resource != null:
		c_resource.on_damage_taken()

	if died_now:
		_die()

func is_in_combat() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if "is_dead" in current_target and bool(current_target.get("is_dead")):
		return false
	return true


func on_player_died() -> void:
	loot_owner_player_id = LootRights.clear_owner()
	c_combat.reset_combat()
	c_ai.force_return()
	velocity = Vector2.ZERO
	if current_target != null:
		_notify_target_change(current_target, null)
	current_target = null
	_prev_target = null
	_clear_direct_attackers()

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
	if not _spawn_initialized:
		c_combat.melee_cooldown = melee_attack_cooldown

	c_combat.ranged_attack_range = ranged_attack_range
	if not _spawn_initialized:
		c_combat.ranged_cooldown = ranged_attack_cooldown
	c_combat.ranged_projectile_scene = ranged_projectile_scene

	c_stats.mob_level = mob_level

	if attack_mode == AttackMode.MELEE:
		c_stats.setup_primary_profile(
			{"str": melee_base_str, "agi": melee_base_agi, "end": melee_base_end, "int": melee_base_int, "per": melee_base_per},
			{"str": melee_str_per_level, "agi": melee_agi_per_level, "end": melee_end_per_level, "int": melee_int_per_level, "per": melee_per_per_level},
			melee_base_defense,
			melee_defense_per_level,
			melee_base_magic_resist,
			melee_magic_resist_per_level
		)
	else:
		c_stats.setup_primary_profile(
			{"str": ranged_base_str, "agi": ranged_base_agi, "end": ranged_base_end, "int": ranged_base_int, "per": ranged_base_per},
			{"str": ranged_str_per_level, "agi": ranged_agi_per_level, "end": ranged_end_per_level, "int": ranged_int_per_level, "per": ranged_per_per_level},
			ranged_base_defense,
			ranged_defense_per_level,
			ranged_base_magic_resist,
			ranged_magic_resist_per_level
		)

func _setup_resource_from_class(class_id_value: String) -> void:
	if c_resource == null:
		return
	c_resource.setup(self)
	c_resource.configure_from_class_id(class_id_value)
	if c_resource.resource_type == "rage":
		c_resource.set_empty()
	else:
		c_resource.set_full()

func _die() -> void:
	if c_stats.is_dead:
		return
	c_stats.is_dead = true
	if current_target != null:
		_notify_target_change(current_target, null)
	current_target = null
	_prev_target = null

	var xp_amount := 0
	if loot_owner_player_id != 0:
		var owner_node: Node = LootRights.get_player_by_instance_id(get_tree(), loot_owner_player_id)
		if owner_node != null and owner_node.is_in_group("player"):
			var player_lvl: int = int(owner_node.get("level"))
			xp_amount = XpSystem.xp_reward_for_kill(BASE_XP_L1_AGGRESSIVE, mob_level, player_lvl)
			xp_amount = int(round(float(xp_amount) * MOB_VARIANT.xp_mult(MOB_VARIANT.clamp_variant(mob_variant))))

	var corpse: Corpse = DeathPipeline.die_and_spawn(
		self,
		loot_owner_player_id,
		xp_amount,
		mob_level,
		loot_profile,
		{ "mob_kind": "aggressive", "mob_variant": mob_variant }
	)

	emit_signal("died", corpse)
	queue_free()

func _on_leash_return_started() -> void:
	# бой сбросился → права на лут больше нет
	loot_owner_player_id = LootRights.clear_owner()
	regen_active = true
	if current_target != null:
		_notify_target_change(current_target, null)
	current_target = null
	_prev_target = null
	_clear_direct_attackers()


func get_faction_id() -> String:
	return faction_id


func _pick_target() -> Node2D:
	var threat_target := ThreatTargeting.pick_target_by_threat(
		self,
		faction_id,
		home_position,
		leash_distance,
		aggro_radius,
		direct_attackers
	)
	if threat_target != null:
		return threat_target
	return FactionTargeting.pick_hostile_target(self, faction_id, aggro_radius)

func _notify_target_change(old_t, new_t) -> void:
	if old_t != null and is_instance_valid(old_t):
		if old_t.is_in_group("player") and old_t.has_method("on_untargeted_by"):
			old_t.call("on_untargeted_by", self)
	if new_t != null and is_instance_valid(new_t):
		if new_t.is_in_group("player") and new_t.has_method("on_targeted_by"):
			new_t.call("on_targeted_by", self)


func _set_loot_owner_if_first(attacker: Node2D) -> void:
	# legacy wrapper (оставлено, чтобы не ломать возможные внешние вызовы)
	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)


func _clear_loot_owner() -> void:
	loot_owner_player_id = LootRights.clear_owner()

func get_danger_meter() -> DangerMeterComponent:
	return c_danger

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _refresh_threat_target() -> void:
	if c_ai == null or c_ai.is_returning():
		return
	if current_target == null:
		return
	if _threat_recheck_timer > 0.0:
		return
	_threat_recheck_timer = THREAT_RECHECK_SEC
	var threat_target := ThreatTargeting.pick_target_by_threat(
		self,
		faction_id,
		home_position,
		leash_distance,
		aggro_radius,
		direct_attackers
	)
	if threat_target != null and threat_target != current_target:
		current_target = threat_target

func _clear_direct_attackers() -> void:
	if direct_attackers.size() > 0:
		direct_attackers.clear()
