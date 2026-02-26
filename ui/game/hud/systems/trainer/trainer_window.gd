extends CanvasLayer

signal hud_visibility_changed(is_open: bool)

const TRAINER_ROW_SCENE := preload("res://ui/game/hud/systems/trainer/trainer_spell_row.tscn")
const TRAINER_SCROLL_TARGET_WIDTH := 664.0
const TRAINER_ROW_HORIZONTAL_PADDING := 16.0
const TRAINER_ROW_SCROLLBAR_RESERVE := 20.0

@onready var panel: Panel = $Root/Panel
@onready var title_label: Label = $Root/Panel/Title
@onready var filter_label: Label = $Root/Panel/FilterRow/FilterLabel
@onready var close_button: Button = $Root/Panel/CloseButton
@onready var filter_option: OptionButton = $Root/Panel/FilterRow/FilterOption
@onready var scroll: ScrollContainer = $Root/Panel/Scroll
@onready var list_vbox: VBoxContainer = $Root/Panel/Scroll/Margin/List

var _player: Player = null
var _spellbook: PlayerSpellbook = null
var _trainer: Node = null
var _trainer_class_id: String = ""
var _ability_db: AbilityDatabase = null
var _tooltip: AbilityTooltip = null
var _tooltip_ability_id: String = ""
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
	_ensure_tooltip_ref()
	if close_button != null and not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	if title_label != null:
		title_label.text = tr("ability.trainer.title")
	if filter_label != null:
		filter_label.text = tr("ability.trainer.filter_label")
	if filter_option != null:
		filter_option.clear()
		filter_option.add_item(tr("ability.trainer.filter.available"))
		filter_option.add_item(tr("ability.trainer.filter.all"))
		filter_option.selected = 0
	if filter_option != null and not filter_option.item_selected.is_connected(_on_filter_changed):
		filter_option.item_selected.connect(_on_filter_changed)
	if scroll != null and not scroll.resized.is_connected(_on_scroll_resized):
		scroll.resized.connect(_on_scroll_resized)
	call_deferred("_sync_scroll_and_rows_width")

func _on_scroll_resized() -> void:
	call_deferred("_sync_scroll_and_rows_width")

func _sync_scroll_and_rows_width() -> void:
	if scroll != null:
		if scroll.offset_right != scroll.offset_left + TRAINER_SCROLL_TARGET_WIDTH:
			scroll.offset_right = scroll.offset_left + TRAINER_SCROLL_TARGET_WIDTH
	_sync_rows_width()

func _sync_rows_width() -> void:
	if list_vbox == null or scroll == null:
		return
	var row_width: float = maxf(1.0, TRAINER_SCROLL_TARGET_WIDTH - TRAINER_ROW_HORIZONTAL_PADDING - TRAINER_ROW_SCROLLBAR_RESERVE)
	for child in list_vbox.get_children():
		if child is Control:
			var row := child as Control
			row.custom_minimum_size.x = row_width
			row.size_flags_horizontal = Control.SIZE_FILL
		if child.has_method("fit_to_scroll_width"):
			child.call_deferred("fit_to_scroll_width", row_width)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if _tooltip == null or not _tooltip.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _tooltip.get_global_rect().has_point(mb.global_position):
				_hide_tooltip()

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
	emit_signal("hud_visibility_changed", true)
	if title_label != null:
		title_label.text = tr("ability.trainer.title")
	_try_refresh_rows()

func close() -> void:
	if not _is_open and not panel.visible:
		return
	_is_open = false
	panel.visible = false
	emit_signal("hud_visibility_changed", false)
	_hide_tooltip()
	_trainer = null
	_player = null
	_spellbook = null


func is_open() -> bool:
	return _is_open and panel != null and panel.visible

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
		push_warning("[TRAINER_UI] AbilityDB returned 0 defs for paladin. AbilityDB may not have loaded core/data/abilities/*.tres.")
	defs.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
		var rank_a: int = int(_spellbook.learned_ranks.get(a.id, 0)) + 1
		var rank_b: int = int(_spellbook.learned_ranks.get(b.id, 0)) + 1
		var req_a: int = 9999
		var req_b: int = 9999
		var rd_a: RankData = _ability_db.get_rank_data(a.id, rank_a)
		var rd_b: RankData = _ability_db.get_rank_data(b.id, rank_b)
		if rd_a != null:
			req_a = rd_a.required_level
		if rd_b != null:
			req_b = rd_b.required_level
		if req_a == req_b:
			return a.get_display_name() < b.get_display_name()
		return req_a < req_b
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
		row.set_data(def, current_rank, max_rank, required_level, cost, can_learn)
		row.name_clicked.connect(_on_row_tooltip_clicked)
		row.icon_clicked.connect(_on_row_tooltip_clicked)
		row.learn_clicked.connect(_on_row_learn_clicked)
	call_deferred("_sync_rows_width")

func _on_row_tooltip_clicked(ability_id: String) -> void:
	if ability_id == "":
		return
	_ensure_tooltip_ref()
	if _tooltip == null:
		return
	if _tooltip.visible and _tooltip_ability_id == ability_id:
		_hide_tooltip()
		return
	var rank := 1
	if _spellbook != null and _ability_db != null:
		var current_rank: int = maxi(0, int(_spellbook.learned_ranks.get(ability_id, 0)))
		var max_rank: int = maxi(1, int(_ability_db.get_max_rank(ability_id)))
		if current_rank < max_rank:
			rank = current_rank + 1
		else:
			rank = max_rank
	_tooltip.show_for(ability_id, rank, get_viewport().get_mouse_position())
	_tooltip_ability_id = ability_id

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.hide_tooltip()
	_tooltip_ability_id = ""

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
		inv_ui.call("show_center_toast", tr("ability.trainer.error.not_enough_coins"))

func _notify_level_locked(level_req: int) -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", tr("ability.trainer.error.level_required").format({"level": level_req}))

func _notify_class_mismatch() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", tr("ability.trainer.error.class_mismatch"))

func _ensure_tooltip_ref() -> void:
	if _tooltip == null or not is_instance_valid(_tooltip):
		_tooltip = get_tree().get_first_node_in_group("ability_tooltip_singleton") as AbilityTooltip
