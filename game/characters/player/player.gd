extends CharacterBody2D
class_name Player

@export var move_speed: float = 220.0

# Auto-attack
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 0.8

# Skill 1 (single-target)
@export var skill_1_range: float = 120.0
@export var skill_1_cooldown: float = 3.0
@export var skill_1_damage_multiplier: float = 2.0
@export var skill_1_mana_cost: int = 12

# Skill 2 (self-heal)
@export var skill_2_cooldown: float = 6.0
@export var skill_2_mana_cost: int = 18
@export var skill_2_heal_amount: int = 35

# Skill 3 (attack buff)
@export var skill_3_cooldown: float = 20.0
@export var skill_3_mana_cost: int = 25
@export var skill_3_duration_sec: float = 600.0
@export var skill_3_attack_bonus: int = 6

# --- Public “state” fields (HUD/UI читает их напрямую) ---
var inventory: Inventory = null

var level: int = 1
var xp: int = 0
var xp_to_next: int = 10

var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 2

var max_mana: int = 60
var mana: int = 60

# --- Components ---
@onready var c_stats: PlayerStats = $Components/Stats as PlayerStats
@onready var c_buffs: PlayerBuffs = $Components/Buffs as PlayerBuffs
@onready var c_combat: PlayerCombat = $Components/Combat as PlayerCombat
@onready var c_skills: PlayerSkills = $Components/Skills as PlayerSkills
@onready var c_inv: PlayerInventoryComponent = $Components/Inventory as PlayerInventoryComponent


func _ready() -> void:
	# setup components
	c_stats.setup(self)
	c_buffs.setup(self)
	c_combat.setup(self)
	c_skills.setup(self)

	# inventory ref (чтобы LootUI/InventoryUI не ломались)
	c_inv.setup(self)
	inventory = c_inv.inventory

	# init stats
	c_stats.recalculate_for_level(true)


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	velocity = input_dir * move_speed
	move_and_slide()


func _process(delta: float) -> void:
	c_buffs.tick(delta)
	c_skills.tick(delta)
	c_combat.tick(delta)


# -----------------------
# Compatibility API (как было раньше)
# -----------------------
func get_attack_damage() -> int:
	return c_combat.get_attack_damage()


func try_cast_skill_1() -> void:
	c_skills.try_cast_skill_1()

func try_cast_skill_2() -> void:
	c_skills.try_cast_skill_2()

func try_cast_skill_3() -> void:
	c_skills.try_cast_skill_3()

func get_skill_1_cooldown_left() -> float:
	return c_skills.get_skill_1_cooldown_left()

func get_skill_2_cooldown_left() -> float:
	return c_skills.get_skill_2_cooldown_left()

func get_skill_3_cooldown_left() -> float:
	return c_skills.get_skill_3_cooldown_left()


# Buffs API (BuffsUI/иконки)
func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	c_buffs.add_or_refresh_buff(id, duration_sec, data)

func remove_buff(id: String) -> void:
	c_buffs.remove_buff(id)

func get_buffs_snapshot() -> Array:
	return c_buffs.get_buffs_snapshot()


# Inventory API (Corpse loot uses this)
func add_gold(amount: int) -> void:
	c_inv.add_gold(amount)

func add_item(item_id: String, amount: int) -> int:
	return c_inv.add_item(item_id, amount)

func get_inventory_snapshot() -> Dictionary:
	return c_inv.get_inventory_snapshot()


# XP / Leveling API
func add_xp(amount: int) -> void:
	c_stats.add_xp(amount)


# Damage API
func take_damage(raw_damage: int) -> void:
	c_stats.take_damage(raw_damage)
