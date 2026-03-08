extends CharacterBody2D
class_name FactionNPC

@export var default_loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
## Helpers below are global classes (class_name). Avoid shadowing them.
const MOB_VARIANT := preload("res://core/stats/mob_variant.gd")
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const Y_SORTING := preload("res://core/render/y_sorting.gd")
const MERCHANT_MODEL_SCENE := preload("res://game/characters/npcs/models/MerchantModel.tscn")
const TRAINER_MODEL_SCENE := preload("res://game/characters/npcs/models/TrainerModel.tscn")

signal died(corpse: Corpse)

@onready var faction_rect: ColorRect = $"ColorRect"
var hp_bar: HealthBarWidget = null
var target_marker: CanvasItem = null
var cast_bar: CastBarWidget = null
var model_highlight: CanvasItem = null
var overlay_bars_widget: OverlayBarsWidget = null
@onready var world_collision: CollisionShape2D = $WorldCollider as CollisionShape2D
@onready var body_hitbox_shape: CollisionShape2D = $BodyHitboxArea/BodyHitbox as CollisionShape2D
@onready var visual_root: Node2D = $Visual as Node2D

const DEFAULT_HP_UI_OFFSET: Vector2 = Vector2.ZERO
const DEFAULT_CAST_BAR_OFFSET: Vector2 = Vector2(0.0, -42.0)

@onready var c_ai: FactionNPCAI = $Components/AI as FactionNPCAI
@onready var c_combat: FactionNPCCombat = $Components/Combat as FactionNPCCombat
@onready var c_stats: FactionNPCStats = $Components/Stats as FactionNPCStats
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent
@onready var c_danger: DangerMeterComponent = $Components/Danger as DangerMeterComponent

const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")
const BASE_XP_L1_FACTION: int = 3
const MERCHANT_BUYBACK_TTL_MSEC: int = 10 * 60 * 1000

enum FighterType { CIVILIAN, COMBATANT }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }
enum AttackMode { MELEE, RANGED }

# -----------------------------
# Identity / runtime state
# -----------------------------
var faction_id: String = "blue"
var fighter_type: int = FighterType.COMBATANT
var interaction_type: int = InteractionType.NONE

var retaliation_target_id: int = 0
var retaliation_active: bool = false

var npc_level: int = 1
var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
var mob_variant: int = MOB_VARIANT.MobVariant.NORMAL
var attack_mode: int = AttackMode.MELEE
var abilities: Array[String] = []
var spell_preset_name_key: String = ""
var c_spell_caster: MobSpellCaster = MobSpellCaster.new()

var home_position: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var proactive_aggro: bool = true
var _prev_target: Node2D = null
var direct_attackers := {} # instance_id -> last_hit_time_sec

# Право на лут: первый удар игрока в текущем бою
var loot_owner_player_id: int = 0

# Merchant buyback storage (per player)
var _merchant_sales: Dictionary = {}
var _merchant_sale_seq: int = 0
var _character_model: Node = null
var _death_sequence_started: bool = false

# Реген после сброса боя
var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.02
const THREAT_RECHECK_SEC: float = 0.25
var _threat_recheck_timer: float = 0.0

# -----------------------------
# Inspector (Common)
# -----------------------------
@export_group("Common")
@export var base_xp: int = 5
@export var xp_per_level: int = 2
@export var move_speed: float = MOVE_SPEED.MOB_BASE
@export var aggro_radius: float = COMBAT_RANGES.AGGRO_RADIUS
@export var leash_distance: float = COMBAT_RANGES.LEASH_DISTANCE

@export_group("Merchant")
@export var merchant_interact_radius: float = 60.0
@export var merchant_preset: MerchantPreset = preload("res://core/trade/presets/merchant_preset_level_1.tres")


# -----------------------------
# Характеристики (как ты просил: сворачиваемые секции + базовые + рост)
# -----------------------------

@export_group("Характеристики: Мирный житель")
@export_subgroup("Базовые характеристики")
@export var civilian_base_str: int = 6
@export var civilian_base_agi: int = 0
@export var civilian_base_end: int = 4
@export var civilian_base_int: int = 0
@export var civilian_base_per: int = 0
@export var civilian_base_defense: int = 1
@export var civilian_base_magic_resist: int = 0
@export var civilian_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
@export var civilian_base_attack_cooldown: float = 1.3
@export_subgroup("Рост базовых характеристик")
@export var civilian_str_per_level: int = 1
@export var civilian_agi_per_level: int = 0
@export var civilian_end_per_level: int = 1
@export var civilian_int_per_level: int = 0
@export var civilian_per_per_level: int = 0
@export var civilian_defense_per_level: int = 1
@export var civilian_magic_resist_per_level: int = 0

@export_group("Характеристики: Боец")
@export_subgroup("Базовые характеристики")
@export var fighter_base_str: int = 11
@export var fighter_base_agi: int = 0
@export var fighter_base_end: int = 6
@export var fighter_base_int: int = 0
@export var fighter_base_per: int = 1
@export var fighter_base_defense: int = 3
@export var fighter_base_magic_resist: int = 0
@export var fighter_base_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
@export var fighter_base_attack_cooldown: float = 1.2
@export_subgroup("Рост базовых характеристик")
@export var fighter_str_per_level: int = 2
@export var fighter_agi_per_level: int = 0
@export var fighter_end_per_level: int = 1
@export var fighter_int_per_level: int = 0
@export var fighter_per_per_level: int = 0
@export var fighter_defense_per_level: int = 1
@export var fighter_magic_resist_per_level: int = 0

@export_group("Характеристики: Маг")
@export_subgroup("Базовые характеристики")
@export var mage_base_str: int = 6
@export var mage_base_agi: int = 0
@export var mage_base_end: int = 4
@export var mage_base_int: int = 8
@export var mage_base_per: int = 1
@export var mage_base_defense: int = 2
@export var mage_base_magic_resist: int = 2
@export var mage_base_attack_range: float = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
@export var mage_base_attack_cooldown: float = 1.6
@export var mage_projectile_scene: PackedScene
@export_subgroup("Рост базовых характеристик")
@export var mage_str_per_level: int = 1
@export var mage_agi_per_level: int = 0
@export var mage_end_per_level: int = 1
@export var mage_int_per_level: int = 2
@export var mage_per_per_level: int = 0
@export var mage_defense_per_level: int = 1
@export var mage_magic_resist_per_level: int = 1

func _ready() -> void:
	add_to_group("faction_units")
	add_to_group("y_sort_entities")
	aggro_radius = COMBAT_RANGES.AGGRO_RADIUS
	leash_distance = COMBAT_RANGES.LEASH_DISTANCE
	mage_base_attack_range = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
	civilian_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	fighter_base_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE

	if home_position == Vector2.ZERO:
		home_position = global_position

	# базовая инициализация, если NPC поставлен вручную
	c_ai.home_position = home_position
	c_ai.aggro_radius = COMBAT_RANGES.AGGRO_RADIUS
	c_ai.leash_distance = COMBAT_RANGES.LEASH_DISTANCE
	c_ai.speed = move_speed
	c_ai.patrol_speed = move_speed * MOVE_SPEED.PATROL_MULTIPLIER
	c_ai.reset_to_idle()

	var cb := Callable(self, "_on_leash_return_started")
	if c_ai.has_signal("leash_return_started") and not c_ai.leash_return_started.is_connected(cb):
		c_ai.leash_return_started.connect(cb)

	_update_faction_color()
	_apply_interaction_visual()
	_setup_resource_from_class(c_stats.class_id if c_stats != null else "")
	c_spell_caster.setup(self)


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


func get_faction_id() -> String:
	return faction_id

func get_display_name() -> String:
	var suffix := String(TranslationServer.translate(spell_preset_name_key)).to_lower()
	if suffix == "":
		return String(name)
	return "%s %s" % [String(name), suffix]

# Спавнер вызывает сразу после instantiate()
func apply_spawn_init(
	spawn_pos: Vector2,
	faction_in: String,
	fighter_in: int,
	interaction_in: int,
	behavior_in: int,
	_aggro_radius_in: float,
	_leash_in: float,
	patrol_pause_in: float,
	_speed_in: float,
	level_in: int,
	loot_profile_in: LootProfile,
	projectile_scene_in: PackedScene,
	class_id_in: String = "",
	growth_profile_id_in: String = "",
	merchant_preset_in: MerchantPreset = null,
	mob_variant_in: int = MOB_VARIANT.MobVariant.NORMAL,
	attack_mode_choice_in: int = AttackMode.MELEE,
	abilities_in: Array[String] = [],
	spell_preset_name_key_in: String = ""
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	faction_id = faction_in
	_update_faction_color()
	fighter_type = fighter_in
	interaction_type = interaction_in
	_apply_interaction_visual()
	npc_level = max(1, level_in)
	mob_variant = MOB_VARIANT.clamp_variant(mob_variant_in)
	loot_profile = loot_profile_in if loot_profile_in != null else default_loot_profile
	merchant_preset = merchant_preset_in if merchant_preset_in != null else merchant_preset
	abilities = abilities_in.duplicate()
	spell_preset_name_key = spell_preset_name_key_in

	# yellow не инициирует бой
	proactive_aggro = (faction_id != "yellow")

	if OS.is_debug_build():
		print("[INIT][FNPC] class_id_in=", class_id_in, " growth_profile_id_in=", growth_profile_id_in, " lvl=", level_in, " pos=", spawn_pos)

	# common params (если спавнер не передал — берём из инспектора)
	c_ai.behavior = behavior_in
	c_ai.aggro_radius = COMBAT_RANGES.AGGRO_RADIUS
	c_ai.leash_distance = COMBAT_RANGES.LEASH_DISTANCE
	c_ai.patrol_radius = COMBAT_RANGES.PATROL_RADIUS
	c_ai.patrol_pause_seconds = patrol_pause_in
	c_ai.speed = move_speed
	c_ai.patrol_speed = move_speed * MOVE_SPEED.PATROL_MULTIPLIER
	c_ai.home_position = home_position
	c_ai.reset_to_idle()

	if c_stats != null:
		c_stats.class_id = class_id_in
		c_stats.growth_profile_id = growth_profile_id_in
		c_stats.mob_variant = mob_variant
	_setup_resource_from_class(class_id_in)
	c_spell_caster.configure(abilities, npc_level)

	# presets + combat mode
	match fighter_type:
		FighterType.CIVILIAN:
			c_stats.apply_primary_preset(
				{"str": civilian_base_str, "agi": civilian_base_agi, "end": civilian_base_end, "int": civilian_base_int, "per": civilian_base_per},
				{"str": civilian_str_per_level, "agi": civilian_agi_per_level, "end": civilian_end_per_level, "int": civilian_int_per_level, "per": civilian_per_per_level},
				civilian_base_defense,
				civilian_defense_per_level,
				civilian_base_magic_resist,
				civilian_magic_resist_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.MELEE
			attack_mode = AttackMode.MELEE
			c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
			c_combat.melee_cooldown = civilian_base_attack_cooldown

		FighterType.COMBATANT:
			var chosen_mode := FactionNPCCombat.AttackMode.MELEE
			if attack_mode_choice_in == AttackMode.RANGED:
				chosen_mode = FactionNPCCombat.AttackMode.RANGED
			elif attack_mode_choice_in == AttackMode.MELEE:
				chosen_mode = FactionNPCCombat.AttackMode.MELEE
			else:
				var role := Progression.get_attack_role_for_class(class_id_in)
				match role:
					"ranged":
						chosen_mode = FactionNPCCombat.AttackMode.RANGED
					"hybrid":
						chosen_mode = FactionNPCCombat.AttackMode.RANGED if randi() % 2 == 0 else FactionNPCCombat.AttackMode.MELEE

			var base_melee := Progression.get_base_melee_attack_interval_for_class(class_id_in)
			var base_ranged := Progression.get_npc_base_ranged_attack_interval_for_class(class_id_in)
			c_combat.melee_cooldown = base_melee

			if chosen_mode == FactionNPCCombat.AttackMode.RANGED:
				c_stats.apply_primary_preset(
					{"str": mage_base_str, "agi": mage_base_agi, "end": mage_base_end, "int": mage_base_int, "per": mage_base_per},
					{"str": mage_str_per_level, "agi": mage_agi_per_level, "end": mage_end_per_level, "int": mage_int_per_level, "per": mage_per_per_level},
					mage_base_defense,
					mage_defense_per_level,
					mage_base_magic_resist,
					mage_magic_resist_per_level
				)
				c_combat.attack_mode = FactionNPCCombat.AttackMode.RANGED
				attack_mode = AttackMode.RANGED
				c_combat.ranged_attack_range = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
				c_combat.ranged_cooldown = base_ranged

				var proj: PackedScene = projectile_scene_in
				if proj == null:
					proj = mage_projectile_scene
				c_combat.ranged_projectile_scene = proj
			else:
				c_stats.apply_primary_preset(
					{"str": fighter_base_str, "agi": fighter_base_agi, "end": fighter_base_end, "int": fighter_base_int, "per": fighter_base_per},
					{"str": fighter_str_per_level, "agi": fighter_agi_per_level, "end": fighter_end_per_level, "int": fighter_int_per_level, "per": fighter_per_per_level},
					fighter_base_defense,
					fighter_defense_per_level,
					fighter_base_magic_resist,
					fighter_magic_resist_per_level
				)
				c_combat.attack_mode = FactionNPCCombat.AttackMode.MELEE
				attack_mode = AttackMode.MELEE
				c_combat.melee_attack_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
				c_combat.melee_cooldown = base_melee

	c_stats.recalc(npc_level)
	c_stats.current_hp = c_stats.max_hp
	_update_hp()


func _process(_delta: float) -> void:
	TargetMarkerHelper.set_marker_visible(target_marker, self)
	if OS.is_debug_build():
		queue_redraw()
	_update_interaction()


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
	draw_arc(center_local, c_combat.ranged_attack_range, 0.0, TAU, 96, ring_color, 1.5, true)
	if c_ai != null and c_ai.aggro_radius > 0.0:
		draw_arc(center_local, c_ai.aggro_radius, 0.0, TAU, 96, Color(1.0, 0.2, 0.2, 0.85), 1.5, true)


func _physics_process(delta: float) -> void:
	_update_visual_render_order()
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
		if c_combat != null:
			c_combat.reset()
		return

	_threat_recheck_timer = max(0.0, _threat_recheck_timer - delta)

	# regen after combat reset (2%/sec)
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		c_stats.current_hp = RegenHelper.tick_regen(c_stats.current_hp, c_stats.max_hp, delta, REGEN_PCT_PER_SEC)
		_update_hp()
		if c_stats.current_hp >= c_stats.max_hp:
			regen_active = false

	# validate current target
	if current_target != null and is_instance_valid(current_target):
		# dead targets are invalid
		if "is_dead" in current_target and bool(current_target.get("is_dead")):
			current_target = null
			retaliation_active = false
			retaliation_target_id = 0
		else:
			# get target faction
			var tf: String = ""
			if current_target.has_method("get_faction_id"):
				tf = String(current_target.call("get_faction_id"))

			# default rule: NPC can fight only HOSTILE factions
			var rel: int = FactionRules.relation(faction_id, tf)
			var allowed: bool = (rel == FactionRules.Relation.HOSTILE)

			# exception: YELLOW fights only the attacker that hit it (retaliation)
			if not allowed and faction_id == "yellow" and retaliation_active:
				if current_target.get_instance_id() == retaliation_target_id:
					allowed = true

			if not allowed:
				current_target = null
				retaliation_active = false
				retaliation_target_id = 0
	else:
		current_target = null
		# если потеряли цель — чистим retaliation (иначе yellow будет "залипать")
		retaliation_active = false
		retaliation_target_id = 0

	# pick target only if proactive aggro is enabled
	# (yellow is non-proactive by design)
	var is_returning := (c_ai != null and c_ai.state == FactionNPCAI.State.RETURN)
	if current_target == null and proactive_aggro and not is_returning:
		current_target = _pick_target()
	if current_target != null and is_instance_valid(current_target):
		if "is_dead" in current_target and bool(current_target.get("is_dead")):
			current_target = null
			regen_active = true

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

	if current_target == null and c_ai != null and c_ai.state != FactionNPCAI.State.RETURN:
		_clear_direct_attackers()

	# AI tick
	c_ai.tick(delta, self, current_target, c_combat, proactive_aggro)
	_update_model_motion(velocity.normalized() if velocity.length() > 0.01 else Vector2.ZERO)

	# combat tick
	if current_target != null and is_instance_valid(current_target):
		var snap: Dictionary = c_stats.get_stats_snapshot()
		if not c_spell_caster.should_block_auto_attack():
			c_combat.tick(delta, self, current_target, snap)
		c_spell_caster.tick(delta, current_target)

	if (current_target == null or not is_instance_valid(current_target)) and c_spell_caster != null and c_spell_caster.is_casting():
		c_spell_caster.interrupt_cast("lost_target")

	if cast_bar != null:
		var casting := c_spell_caster.is_casting()
		var show_cast: bool = casting and _is_combat_visible_for_player()
		cast_bar.set_cast_visible(show_cast)
		cast_bar.set_progress01(c_spell_caster.get_cast_progress() if show_cast else 0.0)
		cast_bar.set_icon_texture(c_spell_caster.get_cast_icon() if show_cast else null)


func _pick_target() -> Node2D:
	var radius: float = COMBAT_RANGES.AGGRO_RADIUS if c_ai != null else 0.0
	var threat_target := ThreatTargeting.pick_target_by_threat(
		self,
		faction_id,
		home_position,
		COMBAT_RANGES.LEASH_DISTANCE,
		radius,
		direct_attackers
	)
	if threat_target != null:
		return threat_target
	return FactionTargeting.pick_hostile_target(self, faction_id, radius)

func take_damage(raw_damage: int) -> void:
	take_damage_from_typed(raw_damage, null, "physical")

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	take_damage_from_typed(raw_damage, attacker, "physical")

func take_damage_from_typed(raw_damage: int, attacker: Node2D, dmg_type: String) -> int:
	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

	if c_stats.is_dead:
		return 0

	regen_active = false

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
	play_model_hurt()
	c_stats.current_hp = max(0, c_stats.current_hp - final)
	var died_now: bool = c_stats.current_hp <= 0
	if final > 0 and attacker != null and is_instance_valid(attacker) and c_stats != null and c_stats.has_method("try_apply_attacker_slow_from_stance"):
		c_stats.call("try_apply_attacker_slow_from_stance", attacker, dmg_type)
	_update_hp()
	if c_resource != null:
		c_resource.on_damage_taken()

	# retaliation
	if attacker != null and is_instance_valid(attacker):
		current_target = attacker
		direct_attackers[attacker.get_instance_id()] = _now_sec()
		if _prev_target != current_target:
			_notify_target_change(_prev_target, current_target)
			_prev_target = current_target
		if c_ai != null:
			c_ai.on_took_damage(attacker)

	# Yellow: реагирует на насилие (как нейтральные)
	if faction_id == "yellow" and attacker != null and is_instance_valid(attacker):
		retaliation_active = true
		retaliation_target_id = attacker.get_instance_id()
		# сразу переводим AI в chase
		if c_ai != null:
			c_ai.state = FactionNPCAI.State.CHASE

	if died_now:
		_die()
	return final

func is_in_combat() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if "is_dead" in current_target and bool(current_target.get("is_dead")):
		return false
	return true

func _die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	if c_spell_caster != null:
		c_spell_caster.interrupt_cast("death")
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	play_model_death()
	if is_queued_for_deletion():
		return
	c_stats.is_dead = true
	if current_target != null:
		_notify_target_change(current_target, null)
	current_target = null
	_prev_target = null

	var timer := get_tree().create_timer(0.9)
	timer.timeout.connect(Callable(self, "_finalize_death"), CONNECT_ONE_SHOT)

func _finalize_death() -> void:
	var p: LootProfile = loot_profile
	if p == null:
		p = default_loot_profile

	var xp_amount := 0
	if loot_owner_player_id != 0:
		var owner_node: Node = LootRights.get_player_by_instance_id(get_tree(), loot_owner_player_id)
		if owner_node != null and owner_node.is_in_group("player"):
			var player_lvl: int = int(owner_node.get("level"))
			xp_amount = XpSystem.xp_reward_for_kill(BASE_XP_L1_FACTION, npc_level, player_lvl)
			xp_amount = int(round(float(xp_amount) * MOB_VARIANT.xp_mult(MOB_VARIANT.clamp_variant(mob_variant))))

	var corpse: Corpse = DeathPipeline.die_and_spawn(
		self,
		loot_owner_player_id,
		xp_amount,
		npc_level,
		p,
		{ "mob_kind": "faction_npc", "mob_variant": mob_variant }
	)

	emit_signal("died", corpse)
	queue_free()

func play_model_hurt() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_hurt"):
		_character_model.call("play_hurt")

func play_model_death() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_death"):
		_character_model.call("play_death")

func play_model_combat_action(action_kind: String, is_moving_now: bool = false) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_combat_action"):
		_character_model.call("play_combat_action", action_kind, is_moving_now, c_stats.class_id if c_stats != null else "")

func _update_model_motion(dir: Vector2) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_move_direction"):
		_character_model.call("set_move_direction", dir)

func update_movement_animation(dir: Vector2, prefer_walk: bool) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_move_direction_mode"):
		_character_model.call("set_move_direction_mode", dir, prefer_walk)
	elif _character_model.has_method("set_move_direction"):
		_character_model.call("set_move_direction", dir)

func _apply_interaction_visual() -> void:
	if visual_root == null:
		return
	if _character_model != null and is_instance_valid(_character_model):
		_character_model.queue_free()
		_character_model = null
	var scene := _resolve_model_scene_for_interaction(interaction_type)
	if scene == null:
		if faction_rect != null:
			faction_rect.visible = true
		_restore_default_overlay_mount()
		return
	var inst := scene.instantiate()
	if inst == null:
		return
	visual_root.add_child(inst)
	_character_model = inst
	if faction_rect != null:
		faction_rect.visible = false
	_apply_collision_profile_from_model(inst)
	_apply_overlay_profile_from_model(inst)

func _resolve_model_scene_for_interaction(value: int) -> PackedScene:
	if value == InteractionType.MERCHANT:
		return MERCHANT_MODEL_SCENE
	if value == InteractionType.TRAINER:
		return TRAINER_MODEL_SCENE
	return null

func _apply_collision_profile_from_model(model: Node) -> void:
	if model == null or not is_instance_valid(model):
		return
	if not model.has_method("get_collision_profile"):
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
		var world_rot_v: Variant = profile.get("world_collision_rotation", world_collision.rotation)
		if world_rot_v is float or world_rot_v is int:
			world_collision.rotation = float(world_rot_v)

	if body_hitbox_shape != null:
		var body_shape_v: Variant = profile.get("body_hitbox_shape", null)
		if body_shape_v is Shape2D:
			body_hitbox_shape.shape = (body_shape_v as Shape2D).duplicate(true)
		var body_offset_v: Variant = profile.get("body_hitbox_offset", body_hitbox_shape.position)
		if body_offset_v is Vector2:
			body_hitbox_shape.position = body_offset_v
		var body_rot_v: Variant = profile.get("body_hitbox_rotation", body_hitbox_shape.rotation)
		if body_rot_v is float or body_rot_v is int:
			body_hitbox_shape.rotation = float(body_rot_v)

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
	if hp_bar != null:
		hp_bar.set_fill_color(Color(0.38720772, 0.18201989, 0.97702104, 1.0))
	var marker_node := model.get_node_or_null("OverlayProfile/TargetMarker")
	if marker_node is CanvasItem:
		target_marker = marker_node as CanvasItem
	var highlight_node := model.get_node_or_null("OverlayProfile/ModelHighlight")
	if highlight_node is CanvasItem:
		model_highlight = highlight_node as CanvasItem
	_update_hp()
	if overlay_bars_widget != null:
		overlay_bars_widget.set_show_name(false)
	if model_highlight != null:
		model_highlight.visible = true
	if cast_bar != null and not c_spell_caster.is_casting():
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)

func _restore_default_overlay_mount() -> void:
	hp_bar = null
	cast_bar = null
	target_marker = null
	model_highlight = null
	overlay_bars_widget = null

func _apply_hp_overlay_defaults() -> void:
	pass

func _apply_hp_overlay_style(_hp_profile: Dictionary) -> void:
	pass

func _update_visual_render_order() -> void:
	if visual_root == null or not is_instance_valid(visual_root):
		return
	visual_root.z_as_relative = false
	visual_root.z_index = Y_SORTING.z_index_for_local_overlap(self, 0)

func _update_hp() -> void:
	if hp_bar == null:
		return
	if c_stats.max_hp <= 0:
		return
	var r: float = clamp(float(c_stats.current_hp) / float(c_stats.max_hp), 0.0, 1.0)
	hp_bar.set_progress01(r)

func _setup_resource_from_class(class_id_value: String) -> void:
	if c_resource == null:
		return
	c_resource.setup(self)
	c_resource.configure_from_class_id(class_id_value)
	if c_resource.resource_type == "rage":
		c_resource.set_empty()
	else:
		c_resource.set_full()

func _set_loot_owner_if_first(attacker: Node2D) -> void:
	# legacy wrapper (оставлено, чтобы не ломать возможные внешние вызовы)
	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

func _clear_loot_owner() -> void:
	loot_owner_player_id = LootRights.clear_owner()

func _on_leash_return_started() -> void:
	# combat reset: lose loot rights + regen on
	loot_owner_player_id = LootRights.clear_owner()
	current_target = null
	if _prev_target != null:
		_notify_target_change(_prev_target, null)
	_prev_target = null
	regen_active = true
	retaliation_active = false
	retaliation_target_id = 0
	_clear_direct_attackers()

func _notify_target_change(old_t, new_t) -> void:
	if old_t != null and is_instance_valid(old_t):
		if old_t.is_in_group("player") and old_t.has_method("on_untargeted_by"):
			old_t.call("on_untargeted_by", self)
	if new_t != null and is_instance_valid(new_t):
		if new_t.is_in_group("player") and new_t.has_method("on_targeted_by"):
			new_t.call("on_targeted_by", self)

func get_danger_meter() -> DangerMeterComponent:
	return c_danger

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _refresh_threat_target() -> void:
	if c_ai == null or c_ai.state != FactionNPCAI.State.CHASE:
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
		COMBAT_RANGES.LEASH_DISTANCE,
		COMBAT_RANGES.AGGRO_RADIUS,
		direct_attackers
	)
	if threat_target != null and threat_target != current_target:
		current_target = threat_target

func _clear_direct_attackers() -> void:
	if direct_attackers.size() > 0:
		direct_attackers.clear()

func _update_interaction() -> void:
	if interaction_type != InteractionType.MERCHANT and interaction_type != InteractionType.TRAINER:
		return
	var p: Node = NodeCache.get_player(get_tree())
	if p == null or not is_instance_valid(p):
		return
	var dist: float = global_position.distance_to(p.global_position)
	var can_interact: bool = false
	if interaction_type == InteractionType.MERCHANT:
		can_interact = _can_trade_with(p)
	else:
		can_interact = _can_train_with(p)
	var can_open: bool = can_interact and dist <= merchant_interact_radius
	if can_open and Input.is_action_just_pressed("loot"):
		if interaction_type == InteractionType.MERCHANT:
			_try_open_merchant(p)
		else:
			_try_open_trainer(p)

func _can_trade_with(player_node: Node) -> bool:
	if player_node == null or c_stats == null or c_stats.is_dead:
		return false
	if is_in_combat():
		return false
	var pf: String = "blue"
	if player_node.has_method("get_faction_id"):
		pf = String(player_node.call("get_faction_id"))
	var rel: int = FactionRules.relation(pf, faction_id)
	if rel == FactionRules.Relation.HOSTILE:
		return false
	return true

func _can_train_with(player_node: Node) -> bool:
	return _can_trade_with(player_node)

func _try_open_merchant(_player_node: Node) -> void:
	var ui := get_tree().get_first_node_in_group("merchant_ui")
	if ui != null and ui.has_method("toggle_for_merchant"):
		ui.call("toggle_for_merchant", self)

func _try_open_trainer(player_node: Node) -> void:
	var ui := get_tree().get_first_node_in_group("trainer_ui")
	if ui == null or not ui.has_method("open_for_trainer"):
		return
	if player_node == null or not is_instance_valid(player_node):
		return
	if not (player_node is Player):
		return
	var trainer_class := ""
	if c_stats != null:
		trainer_class = c_stats.class_id
	if OS.is_debug_build():
		print("[TRAINER] npc_class=", trainer_class, " player_class=", (player_node as Player).class_id, " npc_id=", get_instance_id())
	ui.call("open_for_trainer", self, player_node, (player_node as Player).c_spellbook, trainer_class)


func can_interact_with(player_node: Node) -> bool:
	if interaction_type != InteractionType.MERCHANT and interaction_type != InteractionType.TRAINER:
		return false
	if player_node == null or not is_instance_valid(player_node):
		return false
	if interaction_type == InteractionType.MERCHANT and not _can_trade_with(player_node):
		return false
	if interaction_type == InteractionType.TRAINER and not _can_train_with(player_node):
		return false
	if player_node is Node2D:
		var dist: float = global_position.distance_to((player_node as Node2D).global_position)
		if dist > merchant_interact_radius:
			return false
	return true


func try_interact(player_node: Node) -> void:
	if not can_interact_with(player_node):
		return
	if interaction_type == InteractionType.MERCHANT:
		_try_open_merchant(player_node)
	elif interaction_type == InteractionType.TRAINER:
		_try_open_trainer(player_node)

func get_merchant_preset() -> MerchantPreset:
	return merchant_preset

func get_merchant_title() -> String:
	return ""

func add_merchant_sale(player_id: int, item_id: String, count: int) -> void:
	if player_id == 0 or item_id == "" or count <= 0:
		return
	_prune_merchant_sales(player_id)
	var list: Array = _merchant_sales.get(player_id, [])
	_merchant_sale_seq += 1
	list.append({
		"sale_id": _merchant_sale_seq,
		"id": item_id,
		"count": count,
		"expires_at": Time.get_ticks_msec() + MERCHANT_BUYBACK_TTL_MSEC
	})
	_merchant_sales[player_id] = list

func get_merchant_sales_for_player(player_id: int) -> Array:
	if player_id == 0:
		return []
	_prune_merchant_sales(player_id)
	if not _merchant_sales.has(player_id):
		return []
	return (_merchant_sales[player_id] as Array).duplicate(true)

func take_merchant_sale(player_id: int, sale_id: int) -> Dictionary:
	if player_id == 0:
		return {}
	_prune_merchant_sales(player_id)
	if not _merchant_sales.has(player_id):
		return {}
	var list: Array = _merchant_sales[player_id] as Array
	for i in range(list.size()):
		var entry: Dictionary = list[i] as Dictionary
		if int(entry.get("sale_id", -1)) == sale_id:
			list.remove_at(i)
			if list.is_empty():
				_merchant_sales.erase(player_id)
			else:
				_merchant_sales[player_id] = list
			return entry
	return {}

func _prune_merchant_sales(player_id: int) -> void:
	if not _merchant_sales.has(player_id):
		return
	var list: Array = _merchant_sales[player_id] as Array
	var now: int = Time.get_ticks_msec()
	var filtered: Array = []
	for entry in list:
		if entry is Dictionary:
			var exp: int = int((entry as Dictionary).get("expires_at", 0))
			if exp == 0 or exp > now:
				filtered.append(entry)
	if filtered.is_empty():
		_merchant_sales.erase(player_id)
	else:
		_merchant_sales[player_id] = filtered


func _get_player_faction_id() -> String:
	var p: Node = NodeCache.get_player(get_tree())
	if p != null and p.has_method("get_faction_id"):
		return String(p.call("get_faction_id"))
	return "blue"

func _update_faction_color() -> void:
	if faction_rect == null:
		return

	var player_faction: String = _get_player_faction_id()

	# Yellow/Green — всегда одинаково
	if faction_id == "yellow":
		faction_rect.color = Color(0.55, 0.55, 0.55) # серый
		return
	if faction_id == "green":
		faction_rect.color = Color(1.0, 0.55, 0.0)   # оранжевый
		return

	# Blue/Red — зависит от фракции игрока
	if player_faction == "red":
		# для red-игрока: red = green, blue = red
		if faction_id == "red":
			faction_rect.color = Color(0.2, 0.85, 0.2) # зелёный
		elif faction_id == "blue":
			faction_rect.color = Color(0.9, 0.2, 0.2)  # красный
		else:
			faction_rect.color = Color(0.55, 0.55, 0.55)
		return

	# default: player blue (и любые другие пока считаем как blue)
	# для blue-игрока: blue = green, red = red
	if faction_id == "blue":
		faction_rect.color = Color(0.2, 0.85, 0.2) # зелёный
	elif faction_id == "red":
		faction_rect.color = Color(0.9, 0.2, 0.2)  # красный
	else:
		faction_rect.color = Color(0.55, 0.55, 0.55)


func _is_combat_visible_for_player() -> bool:
	var player_node := NodeCache.get_player(get_tree())
	if player_node == null or not is_instance_valid(player_node):
		return false
	if current_target != null and is_instance_valid(current_target) and current_target == player_node:
		return true
	var player_id := player_node.get_instance_id()
	if direct_attackers.has(player_id):
		return true
	return false

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
