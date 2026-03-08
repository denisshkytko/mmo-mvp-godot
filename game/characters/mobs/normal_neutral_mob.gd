extends CharacterBody2D
class_name NormalNeutralMob

## These helpers are registered as global classes (class_name).
## Avoid shadowing them with local constants.
const MOB_VARIANT := preload("res://core/stats/mob_variant.gd")
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const DEFAULT_RANGED_PROJECTILE_SCENE := preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")
const Y_SORTING := preload("res://core/render/y_sorting.gd")
const OVERLAY_COLORS := preload("res://game/characters/shared/overlay_relation_colors.gd")

const MODEL_SCENE_PATHS := {
	"golems": {
		"earth": "res://game/characters/mobs/models/GolemEarthModel.tscn",
		"ice": "res://game/characters/mobs/models/GolemIceModel.tscn",
		"magma": "res://game/characters/mobs/models/GolemMagmaModel.tscn",
	},
}

signal died(corpse: Corpse)

var hp_bar: HealthBarWidget = null
var target_marker: CanvasItem = null
var cast_bar: CastBarWidget = null
var model_highlight: CanvasItem = null
var overlay_bars_widget: OverlayBarsWidget = null
@onready var world_collision: CollisionShape2D = $WorldCollider as CollisionShape2D
@onready var body_hitbox_shape: CollisionShape2D = $BodyHitboxArea/BodyHitbox as CollisionShape2D
@onready var visual_root: Node2D = get_node_or_null("Visual") as Node2D

var model_group_id: String = "golems"
var model_id: String = "earth"
var _character_model: Node = null
var _active_model_key: String = ""
var _model_scene_cache: Dictionary = {}

@onready var c_ai: NormalNeutralMobAI = $Components/AI as NormalNeutralMobAI
@onready var c_combat: NormalNeutralMobCombat = $Components/Combat as NormalNeutralMobCombat
@onready var c_stats: NormalNeutralMobStats = $Components/Stats as NormalNeutralMobStats
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent
@onready var c_danger: DangerMeterComponent = $Components/Danger as DangerMeterComponent

enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }
enum AttackMode { MELEE, RANGED }

@export_group("Common")
@export var base_xp: int = 3
@export var xp_per_level: int = 1
@export var move_speed: float = MOVE_SPEED.MOB_BASE
@export var aggro_radius: float = COMBAT_RANGES.AGGRO_RADIUS
@export var leash_distance: float = COMBAT_RANGES.LEASH_DISTANCE

# размер тела выбирается спавнером
var body_size: int = BodySize.MEDIUM
var mob_level: int = 1
var attack_mode: int = AttackMode.MELEE
var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_animal_default.tres") as LootProfile
var skin_id: String = ""
var mob_variant: int = MOB_VARIANT.MobVariant.NORMAL
var abilities: Array[String] = []
var spell_preset_name_key: String = ""
var c_spell_caster: MobSpellCaster = MobSpellCaster.new()

var home_position: Vector2 = Vector2.ZERO



const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

# агрессия
var is_aggressive: bool = false
var aggressor: Node2D = null
var _prev_aggressor: Node2D = null
var direct_attackers := {} # instance_id -> last_hit_time_sec

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
@export var small_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
@export var medium_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
@export var large_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
@export var humanoid_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
	aggro_radius = COMBAT_RANGES.AGGRO_RADIUS
	leash_distance = COMBAT_RANGES.LEASH_DISTANCE
	add_to_group("y_sort_entities")
	small_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	medium_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	large_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	humanoid_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	if home_position == Vector2.ZERO:
		home_position = global_position
	if not _spawn_initialized:
		_apply_model_visual()

	# связь с AI: начало RETURN по leash → сброс агрессии + старт регена
	if c_ai != null:
		if not c_ai.leash_return_started.is_connected(_on_leash_return_started):
			c_ai.leash_return_started.connect(_on_leash_return_started)

	# Для мобов из спавнера пересчёт делается в apply_spawn_init.
	# Здесь оставляем только ручную инициализацию.
	c_spell_caster.setup(self)
	if not _spawn_initialized:
		_apply_to_components()
		_setup_resource_from_class(c_stats.class_id if c_stats != null else "")
		c_stats.recalculate_for_level(mob_level)
		c_stats.update_hp_bar(hp_bar)

func _process(_delta: float) -> void:
	TargetMarkerHelper.set_marker_visible(target_marker, self)
	if OS.is_debug_build():
		queue_redraw()


func get_body_hitbox_center_global() -> Vector2:
	if body_hitbox_shape != null:
		return body_hitbox_shape.global_position
	return global_position

func get_sort_anchor_global() -> Vector2:
	return get_body_hitbox_center_global()


func _draw() -> void:
	if not OS.is_debug_build():
		return
	if c_combat == null:
		return
	var center_local := to_local(get_body_hitbox_center_global())
	var ring_color := Color(1.0, 0.9, 0.2, 0.85)
	draw_arc(center_local, c_combat.melee_attack_range, 0.0, TAU, 96, ring_color, 1.5, true)
	draw_arc(center_local, COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE, 0.0, TAU, 96, ring_color, 1.5, true)
	if aggro_radius > 0.0:
		draw_arc(center_local, aggro_radius, 0.0, TAU, 96, Color(1.0, 0.2, 0.2, 0.85), 1.5, true)

func _physics_process(delta: float) -> void:
	_update_visual_render_order()
	update_movement_animation(velocity, false)
	if c_stats.is_dead or c_stats.current_hp <= 0:
		_die()
		return

	if c_stats != null and c_stats.has_method("tick_status_effects"):
		c_stats.call("tick_status_effects", delta)
	if not c_stats.is_dead and c_stats.current_hp <= 0:
		_die()
		return
	if c_stats != null and c_stats.has_method("is_stunned") and bool(c_stats.call("is_stunned")):
		if c_spell_caster != null:
			c_spell_caster.interrupt_cast("stunned")
		if cast_bar != null:
			cast_bar.set_cast_visible(false)
			cast_bar.set_progress01(0.0)
			cast_bar.set_icon_texture(null)
		velocity = Vector2.ZERO
		move_and_slide()
		c_combat.reset_combat()
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
	if aggressor == null and c_ai != null and not c_ai.is_returning():
		_clear_direct_attackers()

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
		c_stats.update_hp_bar(hp_bar)
		if c_stats.current_hp >= c_stats.max_hp:
			regen_active = false

	# AI
	var target: Node2D = aggressor if is_aggressive else null
	c_ai.tick(delta, self, target, c_combat, is_aggressive)

	# атака только если агрессивен
	if is_aggressive and aggressor != null and is_instance_valid(aggressor):
		var snap: Dictionary = c_stats.get_stats_snapshot()
		if not c_spell_caster.should_block_auto_attack():
			c_combat.tick(delta, self, aggressor, snap)
		c_spell_caster.tick(delta, aggressor)

	if (aggressor == null or not is_instance_valid(aggressor)) and c_spell_caster != null and c_spell_caster.is_casting():
		c_spell_caster.interrupt_cast("lost_target")

	if cast_bar != null:
		var casting := c_spell_caster.is_casting()
		var show_cast: bool = casting and _is_combat_visible_for_player()
		cast_bar.set_cast_visible(show_cast)
		cast_bar.set_progress01(c_spell_caster.get_cast_progress() if show_cast else 0.0)
		cast_bar.set_icon_texture(c_spell_caster.get_cast_icon() if show_cast else null)

func _update_visual_render_order() -> void:
	if visual_root == null or not is_instance_valid(visual_root):
		return
	visual_root.z_as_relative = false
	visual_root.z_index = Y_SORTING.z_index_for_local_overlap(self, 0)

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
	_clear_direct_attackers()

# ---------------------------
# Called by Spawner
# ---------------------------
func apply_spawn_init(
	spawn_pos: Vector2,
	behavior_in: int,
	_leash_distance_in: float,
	patrol_pause_in: float,
	_speed_in: float,
	level_in: int,
	body_size_in: int,
	skin_id_in: String,
	loot_profile_in: LootProfile = null,
	class_id_in: String = "",
	growth_profile_id_in: String = "",
	mob_variant_in: int = MOB_VARIANT.MobVariant.NORMAL,
	attack_mode_choice_in: int = AttackMode.MELEE,
	abilities_in: Array[String] = [],
	spell_preset_name_key_in: String = "",
	model_group_id_in: String = "golems",
	model_id_in: String = "earth"
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos
	skin_id = skin_id_in
	if loot_profile_in != null:
		loot_profile = loot_profile_in
	abilities = abilities_in.duplicate()
	spell_preset_name_key = spell_preset_name_key_in
	model_group_id = String(model_group_id_in).to_lower()
	model_id = String(model_id_in).to_lower()
	_apply_model_visual()
	# Common params (speed/leash/aggro) are configured on the mob itself.
	mob_level = max(1, level_in)
	c_spell_caster.configure(abilities, mob_level)
	body_size = body_size_in
	mob_variant = MOB_VARIANT.clamp_variant(mob_variant_in)
	attack_mode = AttackMode.RANGED if attack_mode_choice_in == AttackMode.RANGED else AttackMode.MELEE

	if c_ai != null:
		c_ai.behavior = behavior_in
		c_ai.leash_distance = COMBAT_RANGES.LEASH_DISTANCE
		c_ai.patrol_radius = COMBAT_RANGES.PATROL_RADIUS
		c_ai.patrol_pause_seconds = patrol_pause_in
		c_ai.speed = move_speed
		c_ai.patrol_speed = move_speed * MOVE_SPEED.PATROL_MULTIPLIER
		c_ai.home_position = home_position
		c_ai.reset_to_idle()

	if OS.is_debug_build() and mob_level == 1:
		print("[INIT][NNM] class_id_in=", class_id_in, " growth_profile_id_in=", growth_profile_id_in)

	if c_stats != null:
		c_stats.class_id = class_id_in
		c_stats.growth_profile_id = growth_profile_id_in
		c_stats.mob_variant = mob_variant

	_setup_resource_from_class(class_id_in)
	_apply_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.current_hp = c_stats.max_hp
	c_stats.update_hp_bar(hp_bar)
	_spawn_initialized = true

	is_aggressive = false
	aggressor = null
	regen_active = false
	c_combat.reset_combat()

func _apply_to_components() -> void:
	if c_ai != null:
		c_ai.home_position = home_position
		c_ai.speed = move_speed
		c_ai.patrol_speed = move_speed * MOVE_SPEED.PATROL_MULTIPLIER
		c_ai.leash_distance = COMBAT_RANGES.LEASH_DISTANCE

	# melee параметры + пресет статов по размеру
	# (для NeutralMob — «туловище» задаёт и боевые тайминги)
	match body_size:
		BodySize.SMALL:
			c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
			c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
			c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
			c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
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
	c_combat.attack_mode = attack_mode
	c_combat.ranged_attack_range = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
	c_combat.ranged_cooldown = c_combat.melee_cooldown
	c_combat.ranged_projectile_scene = DEFAULT_RANGED_PROJECTILE_SCENE

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
	take_damage_from_typed(raw_damage, null, "physical")

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	take_damage_from_typed(raw_damage, attacker, "physical")

func take_damage_from_typed(raw_damage: int, attacker: Node2D, dmg_type: String) -> int:
	if c_stats.is_dead:
		return 0

	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)
	if attacker != null and is_instance_valid(attacker):
		direct_attackers[attacker.get_instance_id()] = _now_sec()

	var snap: Dictionary = c_stats.get_stats_snapshot()
	if _roll_evade(snap):
		return 0
	var pct: float
	if dmg_type == "magic":
		pct = float(snap.get("magic_reduction_pct", 0.0))
	else:
		pct = float(snap.get("physical_reduction_pct", 0.0))
	var final: int = int(ceil(float(raw_damage) * (1.0 - pct / 100.0)))
	final = max(1, final)
	final = _apply_shield_block_if_any(final, snap)
	if final <= 0:
		return 0
	c_stats.current_hp = max(0, c_stats.current_hp - final)
	var died_now: bool = c_stats.current_hp <= 0
	if final > 0 and attacker != null and is_instance_valid(attacker) and c_stats != null and c_stats.has_method("try_apply_attacker_slow_from_stance"):
		c_stats.call("try_apply_attacker_slow_from_stance", attacker, dmg_type)
	c_stats.update_hp_bar(hp_bar)
	if _character_model != null and is_instance_valid(_character_model) and _character_model.has_method("play_hurt"):
		_character_model.call("play_hurt")
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
		c_ai.on_took_damage(attacker)
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
			c_ai.on_took_damage(aggressor)

	if died_now:
		_die()
	return final


func _roll_evade(snap: Dictionary) -> bool:
	var evade_pct: float = clamp(float(snap.get("evade_chance_pct", 0.0)), 0.0, 100.0)
	if evade_pct <= 0.0:
		return false
	return randf() * 100.0 < evade_pct

func _apply_shield_block_if_any(damage_after_mitigation: int, snap: Dictionary) -> int:
	if damage_after_mitigation <= 0:
		return 0
	if not _has_left_shield_equipped():
		return damage_after_mitigation
	var block_chance_pct: float = clamp(float(snap.get("block_chance_pct", 0.0)), 0.0, 100.0)
	if block_chance_pct <= 0.0:
		return damage_after_mitigation
	if randf() * 100.0 >= block_chance_pct:
		return damage_after_mitigation
	var block_value: int = max(0, int(round(float((snap.get("derived", {}) as Dictionary).get("block_value", 0.0)))))
	if block_value <= 0:
		return damage_after_mitigation
	return max(0, damage_after_mitigation - block_value)

func _has_left_shield_equipped() -> bool:
	var equip: Dictionary = c_stats.get_equipment_snapshot() if c_stats != null and c_stats.has_method("get_equipment_snapshot") else {}
	if equip.is_empty():
		return false
	var left: Variant = equip.get("weapon_l", null)
	if not (left is Dictionary):
		return false
	var item: Dictionary = left as Dictionary
	var item_id: String = String(item.get("id", ""))
	if item_id == "":
		return false
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return false
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	if String(meta.get("type", "")).to_lower() != "offhand":
		return false
	var offhand: Dictionary = meta.get("offhand", {}) as Dictionary
	return String(offhand.get("slot", "")).to_lower() == "shield"


func is_in_combat() -> bool:
	if aggressor == null or not is_instance_valid(aggressor):
		return false
	if "is_dead" in aggressor and bool(aggressor.get("is_dead")):
		return false
	return true


func _is_combat_visible_for_player() -> bool:
	var player_node := NodeCache.get_player(get_tree())
	if player_node == null or not is_instance_valid(player_node):
		return false
	if aggressor != null and is_instance_valid(aggressor) and aggressor == player_node:
		return true
	var player_id := player_node.get_instance_id()
	if direct_attackers.has(player_id):
		return true
	return false


func on_player_died() -> void:
	if c_spell_caster != null:
		c_spell_caster.interrupt_cast("player_died")
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
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
	_clear_direct_attackers()

# ---------------------------
# Death + loot/xp (как у агрессивного)
# ---------------------------
func _die() -> void:
	if c_spell_caster != null:
		c_spell_caster.interrupt_cast("death")
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	if is_queued_for_deletion():
		return
	c_stats.is_dead = true
	if _character_model != null and is_instance_valid(_character_model) and _character_model.has_method("play_death"):
		_character_model.call("play_death")
	if _prev_aggressor != null:
		_notify_target_change(_prev_aggressor, null)
	_prev_aggressor = null

	var xp_amount := 0
	if loot_owner_player_id != 0:
		var owner_node: Node = LootRights.get_player_by_instance_id(get_tree(), loot_owner_player_id)
		if owner_node != null and owner_node.is_in_group("player"):
			var player_lvl: int = int(owner_node.get("level"))
			xp_amount = XpSystem.xp_reward_for_kill(_base_xp_l1_by_size(), mob_level, player_lvl)
			xp_amount = int(round(float(xp_amount) * MOB_VARIANT.xp_mult(MOB_VARIANT.clamp_variant(mob_variant))))

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
			"mob_variant": mob_variant,
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

func get_danger_meter() -> DangerMeterComponent:
	return c_danger

func get_display_name() -> String:
	var suffix := String(TranslationServer.translate(spell_preset_name_key)).to_lower()
	if suffix == "":
		return String(name)
	return "%s %s" % [String(name), suffix]

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _clear_direct_attackers() -> void:
	if direct_attackers.size() > 0:
		direct_attackers.clear()

func get_corpse_pose_snapshot() -> Dictionary:
	if _character_model != null and is_instance_valid(_character_model) and _character_model.has_method("build_corpse_pose_snapshot"):
		var v: Variant = _character_model.call("build_corpse_pose_snapshot")
		if v is Dictionary:
			return v as Dictionary
	return {}

func play_model_combat_action(action_kind: String, is_moving_now: bool = false) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_combat_action"):
		_character_model.call("play_combat_action", action_kind, is_moving_now, c_stats.class_id if c_stats != null else "")

func update_movement_animation(dir: Vector2, prefer_walk: bool) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_move_direction_mode"):
		_character_model.call("set_move_direction_mode", dir, prefer_walk)
	elif _character_model.has_method("set_move_direction"):
		_character_model.call("set_move_direction", dir)

func _apply_model_visual() -> void:
	if visual_root == null:
		return
	var model_key := "%s:%s" % [model_group_id, model_id]
	if _character_model != null and is_instance_valid(_character_model) and _active_model_key == model_key:
		return
	if _character_model != null and is_instance_valid(_character_model):
		_character_model.queue_free()
		_character_model = null
	_active_model_key = model_key
	var scene := _resolve_model_scene(model_group_id, model_id)
	if scene == null:
		hp_bar = null
		cast_bar = null
		return
	var inst := scene.instantiate()
	if inst == null:
		hp_bar = null
		cast_bar = null
		return
	visual_root.add_child(inst)
	_character_model = inst
	_apply_collision_profile_from_model(inst)
	_apply_overlay_profile_from_model(inst)

func _resolve_model_scene(group_id: String, id: String) -> PackedScene:
	if not MODEL_SCENE_PATHS.has(group_id):
		return null
	var group_map := MODEL_SCENE_PATHS[group_id] as Dictionary
	if not group_map.has(id):
		return null
	var model_path := String(group_map[id])
	if model_path == "":
		return null
	if _model_scene_cache.has(model_path):
		return _model_scene_cache[model_path] as PackedScene
	var loaded := load(model_path)
	if loaded is PackedScene:
		_model_scene_cache[model_path] = loaded
		return loaded as PackedScene
	return null

func _apply_collision_profile_from_model(model: Node) -> void:
	if model == null or not is_instance_valid(model) or not model.has_method("get_collision_profile"):
		return
	var profile_v: Variant = model.call("get_collision_profile")
	if not (profile_v is Dictionary):
		return
	var profile := profile_v as Dictionary
	if world_collision != null:
		var world_shape_v: Variant = profile.get("world_collision_shape", null)
		if world_shape_v is Shape2D:
			world_collision.shape = (world_shape_v as Shape2D).duplicate(true)
		var world_offset_v: Variant = profile.get("world_collision_offset", world_collision.position)
		if world_offset_v is Vector2:
			world_collision.position = world_offset_v
	if body_hitbox_shape != null:
		var body_shape_v: Variant = profile.get("body_hitbox_shape", null)
		if body_shape_v is Shape2D:
			body_hitbox_shape.shape = (body_shape_v as Shape2D).duplicate(true)
		var body_offset_v: Variant = profile.get("body_hitbox_offset", body_hitbox_shape.position)
		if body_offset_v is Vector2:
			body_hitbox_shape.position = body_offset_v

func _apply_overlay_profile_from_model(model: Node) -> void:
	_bind_overlay_widgets_from_model(model)

func _bind_overlay_widgets_from_model(model: Node) -> void:
	hp_bar = null
	cast_bar = null
	target_marker = null
	model_highlight = null
	overlay_bars_widget = null
	if model == null or not is_instance_valid(model):
		return
	overlay_bars_widget = _find_first_by_type(model, OverlayBarsWidget) as OverlayBarsWidget
	hp_bar = _find_first_by_type(model, HealthBarWidget) as HealthBarWidget
	cast_bar = _find_first_by_type(model, CastBarWidget) as CastBarWidget
	var marker_node := model.get_node_or_null("OverlayProfile/TargetMarker")
	if marker_node is CanvasItem:
		target_marker = marker_node as CanvasItem
	var highlight_node := model.get_node_or_null("OverlayProfile/ModelHighlight")
	if highlight_node is CanvasItem:
		model_highlight = highlight_node as CanvasItem
	if hp_bar != null:
		hp_bar.set_fill_color(OVERLAY_COLORS.mob_hp_color(false))
		c_stats.update_hp_bar(hp_bar)
	if overlay_bars_widget != null:
		overlay_bars_widget.set_show_name(false)
	if cast_bar != null and not c_spell_caster.is_casting():
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	if model_highlight != null:
		model_highlight.visible = false
		if model_highlight.has_method("set_colors"):
			var hc := OVERLAY_COLORS.highlight_colors(OVERLAY_COLORS.mob_hp_color(false), 0.5)
			model_highlight.call("set_colors", hc.get("center"), hc.get("edge"))

func _find_first_by_type(root: Node, script_type: Variant) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	for child in root.get_children():
		if is_instance_of(child, script_type):
			return child
		if child is Node:
			var nested := _find_first_by_type(child, script_type)
			if nested != null:
				return nested
	return null
