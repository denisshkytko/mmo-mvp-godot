extends CharacterBody2D
class_name FactionNPC

@export var default_loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
const LootRights := preload("res://core/loot/loot_rights.gd")
const NodeCache := preload("res://core/runtime/node_cache.gd")
const FactionTargeting := preload("res://core/faction/faction_targeting.gd")
const RegenHelper := preload("res://core/combat/regen_helper.gd")
const DeathPipeline := preload("res://core/world/death_pipeline.gd")
const TargetMarkerHelper := preload("res://core/ui/target_marker_helper.gd")

signal died(corpse: Corpse)

@onready var faction_rect: ColorRect = $"ColorRect"
@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@onready var c_ai: FactionNPCAI = $Components/AI as FactionNPCAI
@onready var c_combat: FactionNPCCombat = $Components/Combat as FactionNPCCombat
@onready var c_stats: FactionNPCStats = $Components/Stats as FactionNPCStats

const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

enum FighterType { CIVILIAN, FIGHTER, MAGE }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }

# -----------------------------
# Identity / runtime state
# -----------------------------
var faction_id: String = "blue"
var fighter_type: int = FighterType.FIGHTER
var interaction_type: int = InteractionType.NONE

var retaliation_target_id: int = 0
var retaliation_active: bool = false

var npc_level: int = 1
var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile

var home_position: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var proactive_aggro: bool = true

# Право на лут: первый удар игрока в текущем бою
var loot_owner_player_id: int = 0

# Реген после сброса боя
var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.02

# -----------------------------
# Inspector (Common)
# -----------------------------
@export_group("Common")
@export var base_xp: int = 5
@export var xp_per_level: int = 2
@export var move_speed: float = 120.0
@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0


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
@export var civilian_base_attack_range: float = 55.0
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
@export var fighter_base_attack_range: float = 55.0
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
@export var mage_base_attack_range: float = 260.0
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

	if home_position == Vector2.ZERO:
		home_position = global_position

	# базовая инициализация, если NPC поставлен вручную
	c_ai.home_position = home_position
	c_ai.aggro_radius = aggro_radius
	c_ai.leash_distance = leash_distance
	c_ai.speed = move_speed
	c_ai.reset_to_idle()

	var cb := Callable(self, "_on_leash_return_started")
	if c_ai.has_signal("leash_return_started") and not c_ai.leash_return_started.is_connected(cb):
		c_ai.leash_return_started.connect(cb)

	_update_faction_color()

func get_faction_id() -> String:
	return faction_id

# Спавнер вызывает сразу после instantiate()
func apply_spawn_init(
	spawn_pos: Vector2,
	faction_in: String,
	fighter_in: int,
	interaction_in: int,
	behavior_in: int,
	aggro_radius_in: float,
	leash_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	speed_in: float,
	level_in: int,
	loot_profile_in: LootProfile,
	projectile_scene_in: PackedScene
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	faction_id = faction_in
	_update_faction_color()
	fighter_type = fighter_in
	interaction_type = interaction_in
	npc_level = max(1, level_in)
	loot_profile = loot_profile_in if loot_profile_in != null else default_loot_profile

	# yellow не инициирует бой
	proactive_aggro = (faction_id != "yellow")

	# common params (если спавнер не передал — берём из инспектора)
	c_ai.behavior = behavior_in
	c_ai.aggro_radius = aggro_radius
	c_ai.leash_distance = leash_distance
	c_ai.patrol_radius = patrol_radius_in
	c_ai.patrol_pause_seconds = patrol_pause_in
	c_ai.speed = move_speed
	c_ai.home_position = home_position
	c_ai.reset_to_idle()

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
			c_combat.melee_attack_range = civilian_base_attack_range
			c_combat.melee_cooldown = civilian_base_attack_cooldown

		FighterType.MAGE:
			c_stats.apply_primary_preset(
				{"str": mage_base_str, "agi": mage_base_agi, "end": mage_base_end, "int": mage_base_int, "per": mage_base_per},
				{"str": mage_str_per_level, "agi": mage_agi_per_level, "end": mage_end_per_level, "int": mage_int_per_level, "per": mage_per_per_level},
				mage_base_defense,
				mage_defense_per_level,
				mage_base_magic_resist,
				mage_magic_resist_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.RANGED
			c_combat.ranged_attack_range = mage_base_attack_range
			c_combat.ranged_cooldown = mage_base_attack_cooldown

			var proj: PackedScene = projectile_scene_in
			if proj == null:
				proj = mage_projectile_scene
			c_combat.ranged_projectile_scene = proj

		_:
			c_stats.apply_primary_preset(
				{"str": fighter_base_str, "agi": fighter_base_agi, "end": fighter_base_end, "int": fighter_base_int, "per": fighter_base_per},
				{"str": fighter_str_per_level, "agi": fighter_agi_per_level, "end": fighter_end_per_level, "int": fighter_int_per_level, "per": fighter_per_per_level},
				fighter_base_defense,
				fighter_defense_per_level,
				fighter_base_magic_resist,
				fighter_magic_resist_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.MELEE
			c_combat.melee_attack_range = fighter_base_attack_range
			c_combat.melee_cooldown = fighter_base_attack_cooldown

	c_stats.recalc(npc_level)
	c_stats.current_hp = c_stats.max_hp
	_update_hp()


func _process(_delta: float) -> void:
	# TargetMarker показывает тех, кто сейчас агрессирует на игрока.
	var is_aggro_on_player: bool = false
	if current_target != null and is_instance_valid(current_target):
		is_aggro_on_player = current_target.is_in_group("player")
	TargetMarkerHelper.set_marker_visible(target_marker, is_aggro_on_player)


func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

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
	if current_target == null and proactive_aggro:
		current_target = _pick_target()

	# AI tick
	c_ai.tick(delta, self, current_target, c_combat, proactive_aggro)

	# combat tick
	if current_target != null and is_instance_valid(current_target):
		var snap: Dictionary = c_stats.get_stats_snapshot()
		var aspct: float = float(snap.get("attack_speed_pct", 0.0))
		c_combat.tick(delta, self, current_target, c_stats.attack_value, aspct)


func _pick_target() -> Node2D:
	var radius: float = c_ai.aggro_radius if c_ai != null else 0.0
	return FactionTargeting.pick_hostile_target(self, faction_id, radius)

func take_damage(raw_damage: int) -> void:
	take_damage_from(raw_damage, null)

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

	if c_stats.is_dead:
		return

	regen_active = false

	var died_now: bool = c_stats.apply_damage(raw_damage)
	_update_hp()

	# retaliation
	if attacker != null and is_instance_valid(attacker):
		current_target = attacker

	# Yellow: реагирует на насилие (как нейтральные)
	if faction_id == "yellow" and attacker != null and is_instance_valid(attacker):
		retaliation_active = true
		retaliation_target_id = attacker.get_instance_id()
		# сразу переводим AI в chase
		if c_ai != null:
			c_ai.state = FactionNPCAI.State.CHASE

	if died_now:
		_die()

func _die() -> void:
	if c_stats.is_dead:
		return
	c_stats.is_dead = true

	var p: LootProfile = loot_profile
	if p == null:
		p = default_loot_profile

	var corpse: Corpse = DeathPipeline.die_and_spawn(
		self,
		loot_owner_player_id,
		(base_xp + npc_level * xp_per_level),
		npc_level,
		p,
		{ "mob_kind": "faction_npc" }
	)

	emit_signal("died", corpse)
	queue_free()

func _update_hp() -> void:
	if hp_fill == null:
		return
	if c_stats.max_hp <= 0:
		return
	var r: float = clamp(float(c_stats.current_hp) / float(c_stats.max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * r

func _set_loot_owner_if_first(attacker: Node2D) -> void:
	# legacy wrapper (оставлено, чтобы не ломать возможные внешние вызовы)
	loot_owner_player_id = LootRights.capture_first_player_hit(loot_owner_player_id, attacker)

func _clear_loot_owner() -> void:
	loot_owner_player_id = LootRights.clear_owner()

func _on_leash_return_started() -> void:
	# combat reset: lose loot rights + regen on
	loot_owner_player_id = LootRights.clear_owner()
	current_target = null
	regen_active = true
	retaliation_active = false
	retaliation_target_id = 0


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
