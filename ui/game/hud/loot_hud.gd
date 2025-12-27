extends CanvasLayer

@onready var panel: Control = $Panel
@onready var scroll: ScrollContainer = $Panel/Scroll
@onready var grid: GridContainer = $Panel/Scroll/Grid
@onready var loot_all_button: Button = $Panel/LootAllButton
@onready var close_button: Button = $Panel/CloseButton

var _corpse: Node = null
var _player: Node = null
var _view_map: Array = [] # подтверждает что лежит в каждом UI-слоте
var _range_check_timer: float = 0.0

func _ready() -> void:
	panel.visible = false
	_player = get_tree().get_first_node_in_group("player")
	loot_all_button.pressed.connect(_on_loot_all_pressed)
	close_button.pressed.connect(close)

	# привязка кликов слотов
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		var b: Button = slot_panel.get_node("Button") as Button
		if b != null:
			b.pressed.connect(_on_slot_pressed.bind(i))

func _process(delta: float) -> void:
	if panel.visible and (_corpse == null or not is_instance_valid(_corpse)):
		close()

	if not panel.visible:
		return

	if _corpse == null or not is_instance_valid(_corpse):
		close()
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			close()
			return

	_range_check_timer -= delta
	if _range_check_timer > 0.0:
		return
	_range_check_timer = 0.1

	var corpse_pos: Vector2 = (_corpse as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position
	var radius: float = float(_corpse.interact_radius)

	if player_pos.distance_to(corpse_pos) > radius:
		close()
		return

	_refresh()

func open_for_corpse(corpse: Node) -> void:
	if panel.visible and _corpse == corpse:
		return
	_corpse = corpse
	panel.visible = true
	_range_check_timer = 0.0
	_refresh()

func close() -> void:
	panel.visible = false
	_corpse = null

func toggle_for_corpse(corpse: Node) -> void:
	if panel.visible and _corpse == corpse:
		close()
	else:
		open_for_corpse(corpse)

func is_looting_corpse(corpse: Node) -> bool:
	return panel.visible and _corpse == corpse


func _refresh() -> void:
	if _corpse == null:
		return

	# corpse V2: loot_gold + loot_slots
	var slots: Array = []
	if "loot_slots" in _corpse:
		slots = _corpse.get("loot_slots") as Array

	var gold: int = 0
	if "loot_gold" in _corpse:
		gold = int(_corpse.get("loot_gold"))

	# Собираем view + карту соответствий
	# view_map[i] = {"type":"gold"} или {"type":"item","slot_index":int}
	_view_map.clear()

	var view_count: int = 0

	if gold > 0:
		_view_map.append({"type": "gold"})
		view_count += 1

	for si in range(slots.size()):
		var s: Variant = slots[si]
		if s is Dictionary and String((s as Dictionary).get("type", "")) == "item":
			_view_map.append({"type": "item", "slot_index": si})
			view_count += 1

	# 1) Скролл: если <= 4, отключаем вертикальный скролл (и скроллбар не появится)
	if view_count <= 4:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# 2) Заполняем 6 UI-слотов: пустые — скрываем полностью
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue

		var label: Label = slot_panel.get_node("Text") as Label
		var b: Button = slot_panel.get_node("Button") as Button

		# пусто → скрываем
		if i >= _view_map.size():
			slot_panel.visible = false
			if label != null:
				label.text = ""
			if b != null:
				b.disabled = true
			continue

		# есть лут → показываем
		slot_panel.visible = true
		if b != null:
			b.disabled = false

		var map_d: Dictionary = _view_map[i] as Dictionary
		var t := String(map_d.get("type", ""))

		if t == "gold":
			label.text = "Gold: %d" % gold
		elif t == "item":
			var si: int = int(map_d.get("slot_index", -1))
			if si < 0 or si >= slots.size():
				label.text = ""
				if b != null:
					b.disabled = true
				continue

			var item_d: Dictionary = slots[si] as Dictionary
			var id := String(item_d.get("id", ""))
			var count := int(item_d.get("count", 0))

			var item_name := id
			if has_node("/root/DataDB"):
				var db := get_node("/root/DataDB")
				item_name = db.get_item_name(id)

			label.text = "%s x%d" % [item_name, count]
		else:
			label.text = ""
			if b != null:
				b.disabled = true

	# Если лута не осталось — закрываем
	if (gold <= 0) and (slots == null or slots.is_empty()):
		close()


func _on_slot_pressed(index: int) -> void:
	if _corpse == null or _player == null:
		return
	if index < 0 or index >= _view_map.size():
		return

	# Достаём актуальные данные из трупа
	var gold: int = 0
	if "loot_gold" in _corpse:
		gold = int(_corpse.get("loot_gold"))

	var slots: Array = []
	if "loot_slots" in _corpse:
		slots = _corpse.get("loot_slots") as Array

	var map_d: Dictionary = _view_map[index] as Dictionary
	var t := String(map_d.get("type", ""))

	if t == "gold":
		# забираем только золото
		if gold > 0 and _player.has_method("add_gold"):
			_player.call("add_gold", gold)
		_corpse.set("loot_gold", 0)

	elif t == "item":
		# забираем только 1 item-slot
		var si: int = int(map_d.get("slot_index", -1))
		if si >= 0 and si < slots.size():
			var item_d: Dictionary = slots[si] as Dictionary
			var id := String(item_d.get("id", ""))
			var count := int(item_d.get("count", 0))

			if id != "" and count > 0 and _player.has_method("add_item"):
				_player.call("add_item", id, count)

			# удаляем этот слот из loot_slots
			slots.remove_at(si)
			_corpse.set("loot_slots", slots)

	# Обновляем UI, окно не закрываем
	_refresh()

	# Если лута не осталось — закрываем и помечаем труп пустым
	if _corpse == null or not is_instance_valid(_corpse):
		close()
		return

	var g_v: Variant = _corpse.get("loot_gold")
	var g: int = 0
	if g_v != null:
		g = int(g_v)

	var s_v: Variant = _corpse.get("loot_slots")
	var s: Array = []
	if s_v is Array:
		s = s_v as Array

	if g <= 0 and s.size() == 0:
		if _corpse.has_method("mark_looted"):
			_corpse.call("mark_looted")
		close()


func _on_loot_all_pressed() -> void:
	if _corpse == null or _player == null:
		return
	_corpse.loot_all_to_player(_player)
	close()
