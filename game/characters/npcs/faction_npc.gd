extends CharacterBody2D
class_name FactionNPC

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
var loot_table_id: String = ""

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
@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0
@export var move_speed: float = 120.0


# -----------------------------
# Inspector presets (понятные вкладки)
# (оставляем значения простыми, без сокращений в логике — но переменные так, чтобы было читаемо)
# -----------------------------
@export_group("Civilian: Base Stats")
@export var civilian_base_attack: int = 4
@export var civilian_attack_per_level: int = 1
@export var civilian_base_max_hp: int = 35
@export var civilian_max_hp_per_level: int = 7
@export var civilian_base_defense: int = 1
@export var civilian_defense_per_level: int = 1

@export_group("Fighter: Base Stats")
@export var fighter_base_attack: int = 7
@export var fighter_attack_per_level: int = 2
@export var fighter_base_max_hp: int = 65
@export var fighter_max_hp_per_level: int = 12
@export var fighter_base_defense: int = 3
@export var fighter_defense_per_level: int = 1

@export_group("Mage: Base Stats")
@export var mage_base_attack: int = 8
@export var mage_attack_per_level: int = 2
@export var mage_base_max_hp: int = 50
@export var mage_max_hp_per_level: int = 10
@export var mage_base_defense: int = 2
@export var mage_defense_per_level: int = 1
@export var mage_projectile_scene: PackedScene

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
	loot_table_in: String,
	projectile_scene_in: PackedScene
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos

	faction_id = faction_in
	_update_faction_color()
	fighter_type = fighter_in
	interaction_type = interaction_in
	npc_level = max(1, level_in)
	loot_table_id = loot_table_in

	# yellow не инициирует бой
	proactive_aggro = (faction_id != "yellow")

	# common params (если спавнер не передал — берём из инспектора)
	c_ai.behavior = behavior_in
	c_ai.aggro_radius = aggro_radius_in if aggro_radius_in > 0.0 else aggro_radius
	c_ai.leash_distance = leash_in if leash_in > 0.0 else leash_distance
	c_ai.patrol_radius = patrol_radius_in
	c_ai.patrol_pause_seconds = patrol_pause_in
	c_ai.speed = speed_in if speed_in > 0.0 else move_speed
	c_ai.home_position = home_position
	c_ai.reset_to_idle()

	# presets + combat mode
	match fighter_type:
		FighterType.CIVILIAN:
			c_stats.apply_preset(
				civilian_base_attack, civilian_attack_per_level,
				civilian_base_max_hp, civilian_max_hp_per_level,
				civilian_base_defense, civilian_defense_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.MELEE

		FighterType.MAGE:
			c_stats.apply_preset(
				mage_base_attack, mage_attack_per_level,
				mage_base_max_hp, mage_max_hp_per_level,
				mage_base_defense, mage_defense_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.RANGED

			var proj: PackedScene = projectile_scene_in
			if proj == null:
				proj = mage_projectile_scene
			c_combat.ranged_projectile_scene = proj

		_:
			c_stats.apply_preset(
				fighter_base_attack, fighter_attack_per_level,
				fighter_base_max_hp, fighter_max_hp_per_level,
				fighter_base_defense, fighter_defense_per_level
			)
			c_combat.attack_mode = FactionNPCCombat.AttackMode.MELEE

	c_stats.recalc(npc_level)
	c_stats.current_hp = c_stats.max_hp
	_update_hp()


func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

	# regen after combat reset (2%/sec)
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		var add_hp: int = int(ceil(float(c_stats.max_hp) * REGEN_PCT_PER_SEC * delta))
		c_stats.current_hp = min(c_stats.max_hp, c_stats.current_hp + max(1, add_hp))
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
		c_combat.tick(delta, self, current_target, c_stats.attack_value)


func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF

	for u in get_tree().get_nodes_in_group("faction_units"):
		if u == self:
			continue
		if not (u is Node2D):
			continue

		var n: Node2D = u as Node2D
		if not is_instance_valid(n):
			continue

		if "is_dead" in n and bool(n.get("is_dead")):
			continue

		var tf: String = ""
		if n.has_method("get_faction_id"):
			tf = String(n.call("get_faction_id"))

		if FactionRules.relation(faction_id, tf) != FactionRules.Relation.HOSTILE:
			continue

		var d: float = global_position.distance_to(n.global_position)
		if d <= c_ai.aggro_radius and d < best_d:
			best_d = d
			best = n

	return best

func take_damage(raw_damage: int) -> void:
	take_damage_from(raw_damage, null)

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	_set_loot_owner_if_first(attacker)

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

	var corpse: Corpse = CORPSE_SCENE.instantiate() as Corpse
	if corpse != null:
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		# loot
		var loot: Dictionary = LootSystem.generate_loot(loot_table_id, npc_level)
		if corpse.has_method("set_loot_v2"):
			corpse.call("set_loot_v2", loot)

		# owner gating (corpse lootable only by that player)
		if corpse.has_method("set_loot_owner_player"):
			var p: Node = get_tree().get_first_node_in_group("player")
			if p != null and p.get_instance_id() == loot_owner_player_id:
				corpse.call("set_loot_owner_player", p)
			else:
				corpse.call("set_loot_owner_player", null)

		# XP only if player has loot rights
		var p2: Node = get_tree().get_first_node_in_group("player")
		if p2 != null and p2.get_instance_id() == loot_owner_player_id and p2.has_method("add_xp"):
			p2.call("add_xp", 4 + npc_level)

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self:
			gm.call("clear_target")

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
	if loot_owner_player_id != 0:
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	if not attacker.is_in_group("player"):
		return
	loot_owner_player_id = attacker.get_instance_id()

func _clear_loot_owner() -> void:
	loot_owner_player_id = 0

func _on_leash_return_started() -> void:
	# combat reset: lose loot rights + regen on
	_clear_loot_owner()
	current_target = null
	regen_active = true
	retaliation_active = false
	retaliation_target_id = 0


func _get_player_faction_id() -> String:
	var p: Node = get_tree().get_first_node_in_group("player")
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
