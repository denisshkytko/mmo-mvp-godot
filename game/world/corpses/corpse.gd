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

# Loot (V2)
var loot_gold: int = 0
var loot_slots: Array = [] # [{type:"gold",amount:int} or {type:"item",id:String,count:int}]
var is_looted: bool = false

var _base_color: Color
var _blink_t: float = 0.0


func _ready() -> void:
	_life_timer = despawn_seconds
	_base_color = visual.color

	hint.visible = false
	_player_cached = get_tree().get_first_node_in_group("player") as Node2D


	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func set_loot(data: Dictionary) -> void:
	loot_gold = int(data.get("gold", 0))
	loot_slots.clear()

	# legacy support: previous format had only one item slot
	var item_id: String = String(data.get("item_id", ""))
	var item_count: int = int(data.get("item_count", 0))
	if item_id != "" and item_count > 0:
		loot_slots.append({"type": "item", "id": item_id, "count": item_count})



func set_loot_v2(data: Dictionary) -> void:
	loot_slots.clear()
	loot_gold = int(data.get("gold", 0))

	var slots_v: Variant = data.get("slots", [])
	if not (slots_v is Array):
		return

	# В loot_slots храним ТОЛЬКО предметы.
	# Gold-слоты, если они пришли в массиве, игнорируем,
	# потому что золото хранится отдельно в loot_gold.
	var arr: Array = slots_v as Array
	for v in arr:
		if not (v is Dictionary):
			continue
		var d := v as Dictionary
		if String(d.get("type", "")) == "item":
			loot_slots.append(d)


func has_loot() -> bool:
	if is_looted:
		return false
	return loot_gold > 0 or (loot_slots != null and loot_slots.size() > 0)


func _process(delta: float) -> void:
	# 1) ТАЙМЕР исчезновения ВСЕГДА тикает
	_life_timer -= delta
	if _life_timer <= 0.0:
		emit_signal("despawned")
		queue_free()
		return

	# Fallback: проверяем дистанцию до игрока (на случай, если body_entered не сработал)
	_range_check_timer -= delta
	if _range_check_timer <= 0.0:
		_range_check_timer = 0.1

		var p := get_tree().get_first_node_in_group("player")
		if p != null and is_instance_valid(p):
			var dist := global_position.distance_to((p as Node2D).global_position)
			if dist <= interact_radius:
				_player_in_range = p
			else:
				_player_in_range = null

	# обновим подсказку после дистанционной проверки
	hint.visible = (_player_in_range != null and has_loot())

	# 3) Мигание — только если есть лут И труп виден камерой
	if has_loot() and _is_visible_by_camera():
		_blink_t += delta
		if _blink_t >= 1.0:
			_blink_t = 0.0

		# 0..1 сек: переключаем цвет
		var on: bool = (_blink_t < 0.5)
		visual.color = _base_color.lightened(0.25) if on else _base_color
	else:
		# Если лута нет — НЕ мигаем
		visual.color = _base_color

	# 4) Открывать окно лута можно только если есть лут
	if _player_in_range != null and has_loot() and Input.is_action_just_pressed("loot"):
		var ui_node: Node = get_tree().get_first_node_in_group("loot_ui")
		if ui_node != null and ui_node.has_method("toggle_for_corpse"):
			ui_node.call("toggle_for_corpse", self)


func loot_all_to_player(player: Node) -> void:
	if player == null:
		return

	# золото
	if loot_gold > 0 and player.has_method("add_gold"):
		player.call("add_gold", loot_gold)

	# items (V2)
	for s in loot_slots:
		if not (s is Dictionary):
			continue
		var d := s as Dictionary
		if String(d.get("type", "")) != "item":
			continue

		var id := String(d.get("id", ""))
		var c := int(d.get("count", 0))
		if id != "" and c > 0 and player.has_method("add_item"):
			player.call("add_item", id, c)

	# очистка
	loot_gold = 0
	loot_slots.clear()


	# если окно лута было открыто — пусть LootUI сам закроется (обычно он закрывается после Take All)
	# мигание/подсказка исчезнут автоматически из-за has_loot() == false


func _on_enter(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = body


func _on_exit(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		hint.visible = false


func _is_visible_by_camera() -> bool:
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return true

	var half: Vector2 = vp.get_visible_rect().size * 0.5 * cam.zoom
	var rect := Rect2(cam.global_position - half, half * 2.0)
	return rect.has_point(global_position)


func mark_looted() -> void:
	is_looted = true
	loot_gold = 0
	loot_slots.clear()
