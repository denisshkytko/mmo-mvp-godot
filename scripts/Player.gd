extends CharacterBody2D

@export var move_speed: float = 220.0

# Combat (MVP auto-attack)
@export var attack_range: float = 70.0
@export var attack_damage: int = 25
@export var attack_cooldown: float = 0.8

var inventory: Inventory
var level: int = 1
var xp: int = 0
var xp_to_next: int = 10
var _attack_timer: float = 0.0

func _ready() -> void:
	print("PLAYER READY")
	inventory = Inventory.new()


func _physics_process(_delta: float) -> void:
	# Movement via default Godot actions (arrows, and WASD if you mapped them to ui_*)
	var input_dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	velocity = input_dir * move_speed
	move_and_slide()


func _process(delta: float) -> void:
	# Auto-attack (только если кулдаун прошёл)
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return

	var target := _find_nearest_mob_in_range()
	if target == null:
		return

	target.take_damage(attack_damage)
	_attack_timer = attack_cooldown


func _find_nearest_mob_in_range() -> Node2D:
	var mobs := get_tree().get_nodes_in_group("mobs")
	var best: Node2D = null
	var best_dist: float = attack_range

	for mob in mobs:
		if mob is Node2D:
			var d := global_position.distance_to(mob.global_position)
			if d <= best_dist:
				best_dist = d
				best = mob

	return best


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
	return {
		"gold": inventory.gold,
		"slots": inventory.slots
	}


func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	xp += amount
	print("XP:", xp, "/", xp_to_next)

	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _calc_xp_to_next(level)
		print("LEVEL UP! level:", level, "next:", xp_to_next, "xp carry:", xp)


func _calc_xp_to_next(new_level: int) -> int:
	# простой рост: 10, 15, 20, 25...
	return 10 + (new_level - 1) * 5
