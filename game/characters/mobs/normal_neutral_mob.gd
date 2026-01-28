extends CharacterBody2D
class_name NormalNeutralMob

## These helpers are registered as global classes (class_name).
## Avoid shadowing them with local constants.

signal died(corpse: Corpse)

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@onready var c_ai: NormalNeutralMobAI = $Components/AI as NormalNeutralMobAI
@onready var c_combat: NormalNeutralMobCombat = $Components/Combat as NormalNeutralMobCombat
@onready var c_stats: NormalNeutralMobStats = $Components/Stats as NormalNeutralMobStats
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent

enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

@export_group("Common")
@export var base_xp: int = 3
@export var xp_per_level: int = 1
@export var move_speed: float = 115.0
@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0

# размер тела выбирается спавнером
var body_size: int = BodySize.MEDIUM
var mob_level: int = 1
var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_animal_default.tres") as LootProfile
var skin_id: String = ""

var home_position: Vector2 = Vector2.ZERO



const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

# агрессия
var is_aggressive: bool = false
var aggressor: Node2D = null
var _prev_aggressor: Node2D = null

# Право на лут: первый удар игрока в текущем бою
var loot_owner_player_id: int = 0

# реген
var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.02
var _spawn_initialized: bool = false

# ---------------------------
# ПРЕСЕТЫ СТАТОВ ПО BODY SIZE
# ---------------------------

@export_group("Характеристики: Туловище SMALL")
@export_subgroup("Базовые характеристики")
@export var small_base_str: int = 6
@export var small_base_agi: int = 0
@export var small_base_end: int = 3
@export var small_base_int: int = 0
@export var small_base_per: int = 0
@export var small_base_defense: int = 1
@export var small_base_magic_resist: int = 0
@export var small_base_attack_range: float = 55.0
@export var small_base_attack_cooldown: float = 1.3
@export_subgroup("Рост базовых характеристик")
@export var small_str_per_level: int = 1
@export var small_agi_per_level: int = 0
@export var small_end_per_level: int = 1
@export var small_int_per_level: int = 0
@export var small_per_per_level: int = 0
@export var small_defense_per_level: int = 1
@export var small_magic_resist_per_level: int = 0

@export_group("Характеристики: Туловище MEDIUM")
@export_subgroup("Базовые характеристики")
@export var medium_base_str: int = 8
@export var medium_base_agi: int = 0
@export var medium_base_end: int = 5
@export var medium_base_int: int = 0
@export var medium_base_per: int = 0
@export var medium_base_defense: int = 1
@export var medium_base_magic_resist: int = 0
@export var medium_base_attack_range: float = 55.0
@export var medium_base_attack_cooldown: float = 1.2
@export_subgroup("Рост базовых характеристик")
@export var medium_str_per_level: int = 1
@export var medium_agi_per_level: int = 0
@export var medium_end_per_level: int = 1
@export var medium_int_per_level: int = 0
@export var medium_per_per_level: int = 0
@export var medium_defense_per_level: int = 1
@export var medium_magic_resist_per_level: int = 0

@export_group("Характеристики: Туловище LARGE")
@export_subgroup("Базовые характеристики")
@export var large_base_str: int = 11
@export var large_base_agi: int = 0
@export var large_base_end: int = 7
@export var large_base_int: int = 0
@export var large_base_per: int = 0
@export var large_base_defense: int = 2
@export var large_base_magic_resist: int = 0
@export var large_base_attack_range: float = 60.0
@export var large_base_attack_cooldown: float = 1.5
@export_subgroup("Рост базовых характеристик")
@export var large_str_per_level: int = 2
@export var large_agi_per_level: int = 0
@export var large_end_per_level: int = 1
@export var large_int_per_level: int = 0
@export var large_per_per_level: int = 0
@export var large_defense_per_level: int = 1
@export var large_magic_resist_per_level: int = 0

@export_group("Характеристики: Туловище HUMANOID")
@export_subgroup("Базовые характеристики")
@export var humanoid_base_str: int = 10
@export var humanoid_base_agi: int = 0
@export var humanoid_base_end: int = 5
@export var humanoid_base_int: int = 0
@export var humanoid_base_per: int = 1
@export var humanoid_base_defense: int = 2
@export var humanoid_base_magic_resist: int = 0
@export var humanoid_base_attack_range: float = 55.0
@export var humanoid_base_attack_cooldown: float = 1.2
@export_subgroup("Рост базовых характеристик")
@export var humanoid_str_per_level: int = 2
@export var humanoid_agi_per_level: int = 0
@export var humanoid_end_per_level: int = 1
@export var humanoid_int_per_level: int = 0
@export var humanoid_per_per_level: int = 0
@export var humanoid_defense_per_level: int = 1
@export var humanoid_magic_resist_per_level: int = 0

func _ready() -> void:
	if home_position == Vector2.ZERO:
		home_position = global_position

	# связь с AI: начало RETURN по leash → сброс агрессии + старт регена
	if c_ai != null:
		if not c_ai.leash_return_started.is_connected(_on_leash_return_started):
			c_ai.leash_return_started.connect(_on_leash_return_started)

	# Для мобов из спавнера пересчёт делается в apply_spawn_init.
	# Здесь оставляем только ручную инициализацию.
	if not _spawn_initialized:
		_apply_to_components()
		_setup_resource_from_class(c_stats.class_id if c_stats != null else "")
		c_stats.recalculate_for_level(mob_level)
		c_stats.update_hp_bar(hp_fill)

func _process(_delta: float) -> void:
	# TargetMarker показывает тех, кто сейчас агрессирует на игрока.
	var is_aggro_on_player: bool = false
	if is_aggressive and aggressor != null and is_instance_valid(aggressor):
		is_aggro_on_player = aggressor.is_in_group("player")
	TargetMarkerHelper.set_marker_visible(target_marker, is_aggro_on_player)

func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

	_apply_to_components()

	var prev_has_aggr := (aggressor != null and is_instance_valid(aggressor))
	if aggressor != null and is_instance_valid(aggressor):
		if "is_dead" in aggressor and bool(aggressor.get("is_dead")):
			aggressor = null
			is_aggressive = false
			regen_active = true
	if aggressor != null and not is_instance_valid(aggressor):
		aggressor = null
		is_aggressive = false

	if _prev_aggressor != null and not is_instance_valid(_prev_aggressor):
		_prev_aggressor = null

	var cur_has_aggr := (aggressor != null and is_instance_valid(aggressor))
	if cur_has_aggr:
		regen_active = false
	elif prev_has_aggr and not cur_has_aggr:
		regen_active = true

	if _prev_aggressor != aggressor:
		_notify_target_change(_prev_aggressor, aggressor)
		_prev_aggressor = aggressor

	# реген идёт только когда regen_active=true, и прекращается только когда HP=100%
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		c_stats.current_hp = RegenHelper.tick_regen(c_stats.current_hp, c_stats.max_hp, delta, REGEN_PCT_PER_SEC)
		c_stats.update_hp_bar(hp_fill)
		if c_stats.current_hp >= c_stats.max_hp:
			regen_active = false

	# AI
	var target: Node2D = aggressor if is_aggressive else null
	c_ai.tick(delta, self, target, c_combat, is_aggressive)

	# атака только если агрессивен
	if is_aggressive and aggressor != null and is_instance_valid(aggressor):
		var snap: Dictionary = c_stats.get_stats_snapshot()
		c_combat.tick(delta, self, aggressor, snap)

func _on_leash_return_started() -> void:
	# как ты просил: агрессия сбрасывается сразу при "позвал домой"
	is_aggressive = false
	aggressor = null
	if _prev_aggressor != null:
		_notify_target_change(_prev_aggressor, null)
	_prev_aggressor = null
	# бой сбросился → права на лут больше нет
	loot_owner_player_id = LootRights.clear_owner()
	regen_active = true
	c_combat.reset_combat()

# ---------------------------
# Called by Spawner
# ---------------------------
func apply_spawn_init(
	spawn_pos: Vector2,
	behavior_in: int,
	_leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	_speed_in: float,
	level_in: int,
	body_size_in: int,
	skin_id_in: String,
	loot_profile_in: LootProfile = null,
	class_id_in: String = "",
	growth_profile_id_in: String = ""
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos
	skin_id = skin_id_in
	if loot_profile_in != null:
		loot_profile = loot_profile_in
	# Common params (speed/leash/aggro) are configured on the mob itself.
	mob_level = max(1, level_in)
	body_size = body_size_in

	if c_ai != null:
		c_ai.behavior = behavior_in
		c_ai.leash_distance = leash_distance
		c_ai.patrol_radius = patrol_radius_in
		c_ai.patrol_pause_seconds = patrol_pause_in
		c_ai.speed = move_speed
		c_ai.home_position = home_position
		c_ai.reset_to_idle()

	if OS.is_debug_build() and mob_level == 1:
		print("[INIT][NNM] class_id_in=", class_id_in, " growth_profile_id_in=", growth_profile_id_in)

	if c_stats != null:
		c_stats.class_id = class_id_in
		c_stats.growth_profile_id = growth_profile_id_in

	_setup_resource_from_class(class_id_in)
	_apply_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.current_hp = c_stats.max_hp
	c_stats.update_hp_bar(hp_fill)
	_spawn_initialized = true

	is_aggressive = false
	aggressor = null
	regen_active = false
	c_combat.reset_combat()

func _apply_to_components() -> void:
	if c_ai != null:
		c_ai.home_position = home_position
		c_ai.speed = move_speed
		c_ai.leash_distance = leash_distance

	# melee параметры + пресет статов по размеру
	# (для NeutralMob — «туловище» задаёт и боевые тайминги)
	match body_size:
		BodySize.SMALL:
			c_combat.melee_attack_range = small_base_attack_range
			c_combat.melee_cooldown = small_base_attack_cooldown
			c_stats.apply_body_preset(
				{"str": small_base_str, "agi": small_base_agi, "end": small_base_end, "int": small_base_int, "per": small_base_per},
				{"str": small_str_per_level, "agi": small_agi_per_level, "end": small_end_per_level, "int": small_int_per_level, "per": small_per_per_level},
				small_base_defense,
				small_defense_per_level,
				small_base_magic_resist,
				small_magic_resist_per_level
			)
		BodySize.MEDIUM:
			c_combat.melee_attack_range = medium_base_attack_range
			c_combat.melee_cooldown = medium_base_attack_cooldown
			c_stats.apply_body_preset(
				{"str": medium_base_str, "agi": medium_base_agi, "end": medium_base_end, "int": medium_base_int, "per": medium_base_per},
				{"str": medium_str_per_level, "agi": medium_agi_per_level, "end": medium_end_per_level, "int": medium_int_per_level, "per": medium_per_per_level},
				medium_base_defense,
				medium_defense_per_level,
				medium_base_magic_resist,
				medium_magic_resist_per_level
			)
		BodySize.LARGE:
			c_combat.melee_attack_range = large_base_attack_range
			c_combat.melee_cooldown = large_base_attack_cooldown
			c_stats.apply_body_preset(
				{"str": large_base_str, "agi": large_base_agi, "end": large_base_end, "int": large_base_int, "per": large_base_per},
				{"str": large_str_per_level, "agi": large_agi_per_level, "end": large_end_per_level, "int": large_int_per_level, "per": large_per_per_level},
				large_base_defense,
				large_defense_per_level,
				large_base_magic_resist,
				large_magic_resist_per_level
			)
		_:
			c_combat.melee_attack_range = humanoid_base_attack_range
			c_combat.melee_cooldown = humanoid_base_attack_cooldown
			c_stats.apply_body_preset(
				{"str": humanoid_base_str, "agi": humanoid_base_agi, "end": humanoid_base_end, "int": humanoid_base_int, "per": humanoid_base_per},
				{"str": humanoid_str_per_level, "agi": humanoid_agi_per_level, "end": humanoid_end_per_level, "int": humanoid_int_per_level, "per": humanoid_per_per_level},
				humanoid_base_defense,
				humanoid_defense_per_level,
				humanoid_base_magic_resist,
				humanoid_magic_resist_per_level
			)

	c_combat.melee_stop_distance = 45.0

	c_stats.recalculate_for_level(mob_level)

func _setup_resource_from_class(class_id_value: String) -> void:
	if c_resource == null:
		return
	c_resource.setup(self)
	c_resource.configure_from_class_id(class_id_value)
	if c_resource.resource_type == "rage":
		c_resource.set_empty()
	else:
		c_resource.set_full()


func _mark_spawned() -> void:
	_spawn_initialized = true

func _notify_target_change(old_t, new_t) -> void:
	if old_t != null and is_instance_valid(old_t):
		if old_t.is_in_group("player") and old_t.has_method("on_untargeted_by"):
			old_t.call("on_untargeted_by", self)
	if new_t != null and is_instance_valid(new_t):
		if new_t.is_in_group("player") and new_t.has_method("on_targeted_by"):
			new_t.call("on_targeted_by", self)

# ---------------------------
# Damage API
# ---------------------------
func take_damage(raw_damage: int) -> void:
	# fallback, если кто-то бьёт без attacker
	take_damage_from(raw_damage, null)

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	if c_stats.is_dead:
		return

	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

	var died_now: bool = c_stats.apply_damage(raw_damage)
	c_stats.update_hp_bar(hp_fill)
	if c_resource != null:
		c_resource.on_damage_taken()

	# нейтрал становится агрессивным на атакующего
	if attacker != null and is_instance_valid(attacker):
		is_aggressive = true
		aggressor = attacker
		if _prev_aggressor != aggressor:
			_notify_target_change(_prev_aggressor, aggressor)
			_prev_aggressor = aggressor
		regen_active = false
		c_ai.on_took_damage(self)
	else:
		# если attacker неизвестен — просто агр на игрока (если он есть)
		var p := NodeCache.get_player(get_tree()) as Node2D
		if p != null:
			is_aggressive = true
			aggressor = p
			if _prev_aggressor != aggressor:
				_notify_target_change(_prev_aggressor, aggressor)
				_prev_aggressor = aggressor
			regen_active = false
			c_ai.on_took_damage(self)

	if died_now:
		_die()

func is_in_combat() -> bool:
	if aggressor == null or not is_instance_valid(aggressor):
		return false
	if "is_dead" in aggressor and bool(aggressor.get("is_dead")):
		return false
	return true

func on_player_died() -> void:
	# чтобы нейтралы тоже отпускали
	is_aggressive = false
	aggressor = null
	if _prev_aggressor != null:
		_notify_target_change(_prev_aggressor, null)
	_prev_aggressor = null
	loot_owner_player_id = LootRights.clear_owner()
	regen_active = false
	c_combat.reset_combat()
	c_ai.force_return()
	velocity = Vector2.ZERO

# ---------------------------
# Death + loot/xp (как у агрессивного)
# ---------------------------
func _die() -> void:
	if c_stats.is_dead:
		return
	c_stats.is_dead = true
	if _prev_aggressor != null:
		_notify_target_change(_prev_aggressor, null)
	_prev_aggressor = null

	var xp_amount := 0
	if loot_owner_player_id != 0:
		var owner_node: Node = LootRights.get_player_by_instance_id(get_tree(), loot_owner_player_id)
		if owner_node != null and owner_node.is_in_group("player"):
			var player_lvl: int = int(owner_node.get("level"))
			xp_amount = XpSystem.xp_reward_for_kill(_base_xp_l1_by_size(), mob_level, player_lvl)

	var corpse: Corpse = DeathPipeline.die_and_spawn(
		self,
		loot_owner_player_id,
		xp_amount,
		mob_level,
		loot_profile,
		{
			"mob_kind": "neutral",
			"body_size": body_size,
			"is_humanoid": body_size == BodySize.HUMANOID,
		}
	)

	emit_signal("died", corpse)
	queue_free()

func _base_xp_l1_by_size() -> int:
	match body_size:
		BodySize.SMALL:
			return 2
		BodySize.LARGE:
			return 14
		BodySize.MEDIUM:
			return 10
		BodySize.HUMANOID:
			return 10
		_:
			return 10
