extends Area2D
class_name Corpse

signal despawned

@onready var hint: Label = $Hint
@onready var visual: ColorRect = $Visual

@export var interact_radius: float = 60.0
@export var despawn_seconds: float = 30.0

var _life_timer: float = 0.0
var _player_in_range: Node = null

var _range_check_timer: float = 0.0
var _player_cached: Node2D = null

var _blink_t: float = 0.0

# owner gating
var loot_owner_player_id: int = 0

# V2 loot
var loot_gold: int = 0
var loot_slots: Array = []

func _ready() -> void:
	_life_timer = despawn_seconds
	hint.visible = false

	var p: Node = get_tree().get_first_node_in_group("player")
	_player_cached = p as Node2D

	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func set_loot_owner_player(player_node: Node) -> void:
	if player_node == null:
		loot_owner_player_id = 0
		return
	loot_owner_player_id = player_node.get_instance_id()

func set_loot_v2(loot: Dictionary) -> void:
	# gold хранится отдельно
	loot_gold = int(loot.get("gold", 0))

	# slots в системе лута могут содержать и gold, и items
	# в corpse.loot_slots мы храним ТОЛЬКО items, иначе труп "не пустеет"
	var result_items: Array = []

	var s: Variant = loot.get("slots", [])
	if s is Array:
		var arr: Array = s as Array
		for v in arr:
			if v is Dictionary:
				var d := v as Dictionary
				if String(d.get("type", "")) == "item":
					# дополнительно фильтруем пустые/битые записи
					var id := String(d.get("id", ""))
					var count := int(d.get("count", 0))
					if id != "" and count > 0:
						result_items.append(d)

	loot_slots = result_items


func has_loot() -> bool:
	if loot_gold > 0:
		return true
	if loot_slots == null:
		return false
	if loot_slots.is_empty():
		return false

	# гарантируем что это реально items
	for v in loot_slots:
		if v is Dictionary and String((v as Dictionary).get("type", "")) == "item":
			return true
	return false


func _can_be_looted_by(player_node: Node) -> bool:
	if player_node == null:
		return false
	if not player_node.is_in_group("player"):
		return false
	if loot_owner_player_id == 0:
		return false
	return player_node.get_instance_id() == loot_owner_player_id

func _process(delta: float) -> void:
	# 1) despawn timer
	_life_timer -= delta
	if _life_timer <= 0.0:
		emit_signal("despawned")
		queue_free()
		return

	# 2) range check fallback (всегда с owner gating)
	_range_check_timer -= delta
	if _range_check_timer <= 0.0:
		_range_check_timer = 0.1

		# Не дергаем get_first_node_in_group() постоянно.
		# Для текущего прототипа игрок один, поэтому достаточно обновлять
		# кеш только если ссылка отсутствует или стала невалидной.
		if _player_cached == null or not is_instance_valid(_player_cached):
			var p: Node = get_tree().get_first_node_in_group("player")
			_player_cached = p as Node2D

		if _player_cached != null and is_instance_valid(_player_cached):
			var dist: float = global_position.distance_to(_player_cached.global_position)
			if dist <= interact_radius and has_loot() and _can_be_looted_by(_player_cached):
				_player_in_range = _player_cached
			else:
				_player_in_range = null
		else:
			_player_in_range = null

	# 3) hint (строго по праву на лут)
	hint.visible = (_player_in_range != null and has_loot() and _can_be_looted_by(_player_in_range))
	if hint.visible and Input.is_action_just_pressed("loot"):
		_try_open_loot()

	# 4) blink (только если игрок реально может лутать)
	if _player_cached != null and has_loot() and _can_be_looted_by(_player_cached) and _is_visible_by_camera():
		_blink_t += delta
		var k: float = 0.5 + 0.5 * sin(_blink_t * 9.0)
		visual.modulate.a = lerp(0.35, 1.0, k)
	else:
		visual.modulate.a = 1.0

func _on_enter(body: Node) -> void:
	if not (body != null and body.is_in_group("player")):
		return
	# НЕ ставим игрока "в рендж", если он не owner
	if has_loot() and _can_be_looted_by(body):
		_player_in_range = body
	else:
		_player_in_range = null

func _on_exit(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null

func _is_visible_by_camera() -> bool:
	# упрощённо: если на экране — считаем visible
	# у тебя это уже было в проекте, оставляю поведение эквивалентным
	return true


func _try_open_loot() -> void:
	# Открываем лут строго если:
	# - игрок в радиусе
	# - у трупа есть лут
	# - игрок имеет право лутать
	if _player_cached == null or not is_instance_valid(_player_cached):
		return
	if not has_loot():
		return
	if not _can_be_looted_by(_player_cached):
		return

	var loot_ui := get_tree().get_first_node_in_group("loot_ui")
	if loot_ui == null:
		return

	# В LootHUD у тебя есть toggle_for_corpse(corpse)
	if loot_ui.has_method("toggle_for_corpse"):
		loot_ui.call("toggle_for_corpse", self)


func loot_all_to_player(player_node: Node) -> void:
	# Используется кнопкой "Забрать всё" из LootHUD
	if player_node == null:
		return
	if not _can_be_looted_by(player_node):
		return

	if loot_gold > 0 and player_node.has_method("add_gold"):
		player_node.call("add_gold", loot_gold)
	loot_gold = 0

	if loot_slots != null and loot_slots.size() > 0 and player_node.has_method("add_item"):
		for s in loot_slots:
			if s is Dictionary and String((s as Dictionary).get("type", "")) == "item":
				var id := String((s as Dictionary).get("id", ""))
				var count := int((s as Dictionary).get("count", 0))
				if id != "" and count > 0:
					player_node.call("add_item", id, count)

	loot_slots = []
	mark_looted()


func mark_looted() -> void:
	# Помечаем труп полностью пустым:
	# - больше не мигает
	# - подсказка не появляется
	loot_gold = 0
	loot_slots = []
	loot_owner_player_id = 0
	_player_in_range = null
	hint.visible = false
	visual.modulate.a = 1.0
