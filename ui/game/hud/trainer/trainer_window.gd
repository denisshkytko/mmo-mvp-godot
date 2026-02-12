extends CanvasLayer

const TRAINER_ROW_SCENE := preload("res://ui/game/hud/trainer/trainer_spell_row.tscn")

@onready var panel: Panel = $Root/Panel
@onready var title_label: Label = $Root/Panel/Title
@onready var close_button: Button = $Root/Panel/CloseButton
@onready var filter_option: OptionButton = $Root/Panel/FilterRow/FilterOption
@onready var list_vbox: VBoxContainer = $Root/Panel/Scroll/Margin/List

var _player: Player = null
var _spellbook: PlayerSpellbook = null
var _trainer: Node = null
var _trainer_class_id: String = ""
var _ability_db: AbilityDatabase = null
var _tooltip: AbilityTooltip = null
var _is_open: bool = false
var _db_ready: bool = false

func _ready() -> void:
	add_to_group("trainer_ui")
	panel.visible = false
	_ability_db = get_node_or_null("/root/AbilityDB") as AbilityDatabase
	if _ability_db != null:
		if _ability_db.is_ready:
			_db_ready = true
		elif not _ability_db.initialized.is_connected(_on_db_ready):
			_ability_db.initialized.connect(_on_db_ready)
	_tooltip = get_tree().get_first_node_in_group("ability_tooltip_singleton") as AbilityTooltip
	if close_button != null and not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	if filter_option != null:
		filter_option.clear()
		filter_option.add_item("Доступные")
		filter_option.add_item("Все")
		filter_option.selected = 0
	if filter_option != null and not filter_option.item_selected.is_connected(_on_filter_changed):
		filter_option.item_selected.connect(_on_filter_changed)

func open_for_trainer(trainer_node: Node, player: Player, spellbook: PlayerSpellbook, trainer_class_id: String) -> void:
	_trainer = trainer_node
	_player = player
	_spellbook = spellbook
	_trainer_class_id = trainer_class_id
	if _player == null or _spellbook == null:
		return
	if _player.class_id != _trainer_class_id:
		_notify_class_mismatch()
		close()
		return
	_is_open = true
	panel.visible = true
	if title_label != null:
		title_label.text = "Тренер"
	_try_refresh_rows()

func close() -> void:
	_is_open = false
	panel.visible = false
	if _tooltip != null:
		_tooltip.hide_tooltip()
	_trainer = null
	_player = null
	_spellbook = null

func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _trainer != null and not is_instance_valid(_trainer):
		close()
		return
	if _trainer != null and _player != null:
		if _trainer.has_method("can_interact_with"):
			if not bool(_trainer.call("can_interact_with", _player)):
				close()
				return

func _on_filter_changed(_idx: int) -> void:
	_try_refresh_rows()

func _on_db_ready() -> void:
	_db_ready = true
	if _is_open:
		_refresh_rows()

func _try_refresh_rows() -> void:
	if _ability_db == null:
		return
	if not _ability_db.is_ready:
		return
	_db_ready = true
	_refresh_rows()

func _refresh_rows() -> void:
	if list_vbox == null:
		return
	for child in list_vbox.get_children():
		child.queue_free()
	if _ability_db == null or _player == null or _spellbook == null:
		return
	if OS.is_debug_build():
		print("[TRAINER_UI] refresh. db_ready=", _ability_db.is_ready, " class=", _trainer_class_id)
	var defs := _ability_db.get_abilities_for_class(_trainer_class_id)
	if OS.is_debug_build():
		print("[TRAINER_UI] defs_count=", defs.size(), " class=", _trainer_class_id)
	if defs.size() == 0 and _trainer_class_id == "paladin":
		push_warning("[TRAINER_UI] AbilityDB returned 0 defs for paladin. AbilityDB may not have loaded data/abilities/*.tres.")
	defs.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
		return a.get_display_name() < b.get_display_name()
	)
	var show_available_only := filter_option != null and filter_option.selected == 0
	for def in defs:
		var current_rank := int(_spellbook.learned_ranks.get(def.id, 0))
		var max_rank := def.get_max_rank()
		if max_rank <= 0:
			continue
		var next_rank := current_rank + 1
		var rank_data := _ability_db.get_rank_data(def.id, next_rank)
		var required_level := 1
		var cost := 0
		if rank_data != null:
			required_level = rank_data.required_level
			cost = rank_data.train_cost_gold
		var can_learn := next_rank <= max_rank and _player.level >= required_level and _has_gold(cost)
		if show_available_only and not can_learn:
			continue
		var row := TRAINER_ROW_SCENE.instantiate()
		list_vbox.add_child(row)
		row.set_data(def, current_rank, max_rank, cost, can_learn)
		row.name_clicked.connect(_on_row_name_clicked)
		row.learn_clicked.connect(_on_row_learn_clicked)

func _on_row_name_clicked(ability_id: String) -> void:
	if _tooltip == null:
		return
	var rank := 1
	if _spellbook != null:
		rank = max(1, int(_spellbook.learned_ranks.get(ability_id, 0)))
	_tooltip.show_for(ability_id, rank, get_viewport().get_mouse_position())

func _on_row_learn_clicked(ability_id: String) -> void:
	if _ability_db == null or _player == null or _spellbook == null:
		return
	var def := _ability_db.get_ability(ability_id)
	if def == null:
		return
	var current_rank := int(_spellbook.learned_ranks.get(ability_id, 0))
	var max_rank := def.get_max_rank()
	if current_rank >= max_rank:
		return
	var next_rank := current_rank + 1
	var rank_data := _ability_db.get_rank_data(ability_id, next_rank)
	if rank_data != null:
		if _player.level < rank_data.required_level:
			_notify_level_locked(rank_data.required_level)
			return
		if not _has_gold(rank_data.train_cost_gold):
			_notify_not_enough_gold()
			return
		if rank_data.train_cost_gold > 0:
			_player.add_gold(-rank_data.train_cost_gold)
	_spellbook.learn_next_rank(ability_id, max_rank)
	_refresh_rows()

func _has_gold(cost: int) -> bool:
	if _player == null or cost <= 0:
		return true
	if not _player.has_method("get_inventory_snapshot"):
		return false
	var snap: Dictionary = _player.call("get_inventory_snapshot") as Dictionary
	return int(snap.get("gold", 0)) >= cost

func _notify_not_enough_gold() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", "Недостаточно монет")

func _notify_level_locked(level_req: int) -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", "Нужен уровень %d" % level_req)

func _notify_class_mismatch() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", "Тренер не для вашего класса")
