extends CharacterBody2D

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
@export var skill_2_heal_amount: int = 35   # плоское лечение (потом можно сделать % или от spellpower)

var inventory: Inventory

# Progression
var level: int = 1
var xp: int = 0
var xp_to_next: int = 10

# Stats
var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 2

# Mana
var max_mana: int = 60
var mana: int = 60

# Timers
var _attack_timer: float = 0.0
var _skill_1_timer: float = 0.0
var _skill_2_timer: float = 0.0


func _ready() -> void:
	inventory = Inventory.new()
	_recalculate_stats_for_level()
	current_hp = max_hp
	mana = max_mana


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
	# cooldown timers
	_attack_timer = max(0.0, _attack_timer - delta)
	_skill_1_timer = max(0.0, _skill_1_timer - delta)
	_skill_2_timer = max(0.0, _skill_2_timer - delta)

	# keyboard hotkeys
	if Input.is_action_just_pressed("skill_1"):
		try_cast_skill_1()

	if Input.is_action_just_pressed("skill_2"):
		try_cast_skill_2()

	# Auto-attack: only if cooldown ready and target exists and is in range
	if _attack_timer > 0.0:
		return

	var target := _get_current_target()
	if target == null:
		return

	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range:
		return

	_apply_damage_to_target(target, get_attack_damage())
	_attack_timer = attack_cooldown


func get_attack_damage() -> int:
	return attack


# -----------------------
# Skill API
# -----------------------
func try_cast_skill_1() -> void:
	if _skill_1_timer > 0.0:
		return
	if mana < skill_1_mana_cost:
		return

	var target := _get_skill_target_in_range()
	if target == null:
		return

	var dmg: int = int(round(float(get_attack_damage()) * skill_1_damage_multiplier))
	_apply_damage_to_target(target, dmg)

	mana = max(0, mana - skill_1_mana_cost)
	_skill_1_timer = skill_1_cooldown


func try_cast_skill_2() -> void:
	# Self heal
	if _skill_2_timer > 0.0:
		return
	if mana < skill_2_mana_cost:
		return
	if current_hp >= max_hp:
		return  # не тратим ману, если фулл хп

	current_hp = min(max_hp, current_hp + skill_2_heal_amount)
	mana = max(0, mana - skill_2_mana_cost)
	_skill_2_timer = skill_2_cooldown


func get_skill_1_cooldown_left() -> float:
	return _skill_1_timer

func get_skill_2_cooldown_left() -> float:
	return _skill_2_timer


func _apply_damage_to_target(target: Node2D, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.call("take_damage", dmg)


# -----------------------
# Inventory API (Corpse loot uses this)
# -----------------------
func add_gold(amount: int) -> void:
	if inventory == null:
		return
	inventory.add_gold(amount)

func add_item(item_id: String, amount: int) -> int:
	if inventory == null:
		return amount
	return inventory.add_item(item_id, amount)

func get_inventory_snapshot() -> Dictionary:
	if inventory == null:
		return {"gold": 0, "slots": []}
	return {"gold": inventory.gold, "slots": inventory.slots}


# -----------------------
# XP / Leveling API (Mob uses this)
# -----------------------
func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _calc_xp_to_next(level)
		_recalculate_stats_for_level()


func _calc_xp_to_next(new_level: int) -> int:
	return 10 + (new_level - 1) * 5


func _recalculate_stats_for_level() -> void:
	max_hp = 100 + (level - 1) * 15
	attack = 10 + (level - 1) * 3
	defense = 2 + (level - 1) * 1
	max_mana = 60 + (level - 1) * 8

	# MVP: full restore on level up
	current_hp = max_hp
	mana = max_mana


# -----------------------
# Target helpers
# -----------------------
func _get_skill_target_in_range() -> Node2D:
	var gm := get_tree().get_first_node_in_group("game_manager")

	# 1) If current target exists and in skill range -> use it
	if gm != null and gm.has_method("get_target"):
		var t = gm.call("get_target")
		if t != null and t is Node2D and is_instance_valid(t):
			var dist := global_position.distance_to((t as Node2D).global_position)
			if dist <= skill_1_range:
				return t as Node2D

	# 2) Otherwise pick nearest mob in skill range
	var mobs := get_tree().get_nodes_in_group("mobs")
	var best: Node2D = null
	var best_dist: float = skill_1_range

	for mob in mobs:
		if mob is Node2D:
			var m := mob as Node2D
			var d := global_position.distance_to(m.global_position)
			if d <= best_dist:
				best_dist = d
				best = m

	# 3) If found - set as target
	if best != null and gm != null and gm.has_method("set_target"):
		gm.call("set_target", best)

	return best


func _get_current_target() -> Node2D:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null or not gm.has_method("get_target"):
		return null

	var t = gm.call("get_target")
	if t != null and t is Node2D and is_instance_valid(t):
		return t as Node2D

	return null


func take_damage(raw_damage: int) -> void:
	var dmg: int = max(1, raw_damage - defense)
	current_hp = max(0, current_hp - dmg)

	if current_hp <= 0:
		_on_death()

func _on_death() -> void:
	current_hp = max_hp
	mana = max_mana
