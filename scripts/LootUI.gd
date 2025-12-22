extends CanvasLayer

@onready var panel: Control = $Panel
@onready var gold_label: Label = $Panel/GoldLabel
@onready var item_label: Label = $Panel/ItemLabel
@onready var loot_all_button: Button = $Panel/LootAllButton
@onready var close_button: Button = $Panel/CloseButton

var _corpse: Node = null
var _player: Node = null
var _range_check_timer: float = 0.0

func _ready() -> void:
	panel.visible = false
	_player = get_tree().get_first_node_in_group("player")
	loot_all_button.pressed.connect(_on_loot_all_pressed)
	close_button.pressed.connect(close)

func _process(_delta: float) -> void:
	if panel.visible and (_corpse == null or not is_instance_valid(_corpse)):
		close()
	
	if not panel.visible:
		return

	# если труп исчез (залутан/удалён) — закрыть
	if _corpse == null or not is_instance_valid(_corpse):
		close()
		return

	# если игрок исчез (перезагрузка сцены) — переподхватить или закрыть
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			close()
			return

	# проверяем дистанцию не каждый кадр, а 10 раз в секунду
	_range_check_timer -= _delta
	if _range_check_timer > 0.0:
		return
	_range_check_timer = 0.1

	var corpse_pos: Vector2 = (_corpse as Node2D).global_position
	var player_pos: Vector2 = (_player as Node2D).global_position

	var radius: float = float(_corpse.interact_radius)

	if player_pos.distance_to(corpse_pos) > radius:
		close()
		return

	# обновляем текст, если хочешь (не обязательно постоянно)
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

func _refresh() -> void:
	if _corpse == null:
		return

	# читаем поля трупа
	var gold := int(_corpse.loot_gold)
	var item_id := String(_corpse.loot_item_id)
	var count := int(_corpse.loot_item_count)

	gold_label.text = "gold: %d" % gold
	item_label.text = "%s x%d" % [item_id, count]

func _on_loot_all_pressed() -> void:
	if _corpse == null or _player == null:
		return

	_corpse.loot_all_to_player(_player)
	close()


func toggle_for_corpse(corpse: Node) -> void:
	if panel.visible and _corpse == corpse:
		close()
	else:
		open_for_corpse(corpse)


func is_looting_corpse(corpse: Node) -> bool:
	return panel.visible and _corpse == corpse
