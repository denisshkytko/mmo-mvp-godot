extends Control

const SPELL_LIST_ITEM_SCENE := preload("res://ui/game/hud/character/spells/spell_list_item.tscn")

@onready var spells_grid: GridContainer = $SpellsVBox/SpellsPanelA/SpellsVBox/SpellsMargin/SpellsScroll/SpellsGrid
@onready var loadout_pad: Control = $SpellsVBox/SpellsPanelB/LoadoutMargin/LoadoutPadRoot
@onready var filter_option: OptionButton = $SpellsVBox/SpellsPanelA/SpellsVBox/SpellFilterOption

var _player: Player = null
var _spellbook: PlayerSpellbook = null
var _ability_db: AbilityDatabase = null
var _tooltip: AbilityTooltip = null
var _selected_ability_id: String = ""
var _tooltip_ability_id: String = ""
var _flow_router: Node = null
var _db_ready: bool = false
var _player_ready: bool = false
var _filter_index: int = 0

func _ready() -> void:
	if filter_option != null and filter_option.item_count == 0:
		filter_option.add_item("Все")
		filter_option.add_item("Активные")
		filter_option.add_item("Ауры/бафы")
		filter_option.select(0)
	if filter_option != null and not filter_option.item_selected.is_connected(_on_filter_selected):
		filter_option.item_selected.connect(_on_filter_selected)

	_flow_router = get_node_or_null("/root/FlowRouter")
	if _flow_router != null and _flow_router.has_signal("player_spawned") and not _flow_router.player_spawned.is_connected(_on_player_spawned):
		_flow_router.player_spawned.connect(_on_player_spawned)

	_ability_db = get_node_or_null("/root/AbilityDB") as AbilityDatabase
	if _ability_db != null:
		if _ability_db.is_ready:
			_db_ready = true
		else:
			if not _ability_db.initialized.is_connected(_on_ability_db_ready):
				_ability_db.initialized.connect(_on_ability_db_ready)

	_ensure_tooltip_ref()
	if loadout_pad != null and loadout_pad.has_signal("slot_pressed") and not loadout_pad.slot_pressed.is_connected(_on_slot_pressed):
		loadout_pad.slot_pressed.connect(_on_slot_pressed)

	var existing_player := get_tree().get_first_node_in_group("player") as Player
	if existing_player != null:
		_on_player_spawned(existing_player, null)

	_try_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _tooltip == null or not _tooltip.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _tooltip.get_global_rect().has_point(mb.global_position):
				_hide_tooltip()

func _on_player_spawned(player: Node, _gm: Node) -> void:
	if not (player is Player):
		return
	if _spellbook != null and _spellbook.spellbook_changed.is_connected(_on_spellbook_changed):
		_spellbook.spellbook_changed.disconnect(_on_spellbook_changed)
	_player = player as Player
	_spellbook = _player.c_spellbook
	_player_ready = _spellbook != null
	if _spellbook != null and not _spellbook.spellbook_changed.is_connected(_on_spellbook_changed):
		_spellbook.spellbook_changed.connect(_on_spellbook_changed)
	if OS.is_debug_build() and _spellbook != null:
		print("[UI] bound to player. class=", _player.class_id, " learned=", _spellbook.learned_ranks.size())
	_try_refresh()

func _on_ability_db_ready() -> void:
	_db_ready = true
	if OS.is_debug_build() and _ability_db != null:
		print("[UI] AbilityDB ready. abilities=", _ability_db.abilities.size())
	_try_refresh()

func _on_spellbook_changed() -> void:
	_try_refresh()

func _try_refresh() -> void:
	if not _db_ready or not _player_ready:
		return
	_refresh_all()

func _refresh_all() -> void:
	_refresh_list()
	_refresh_loadout()
	_update_assignment_visuals()

func _refresh_list() -> void:
	if spells_grid == null:
		return
	for child in spells_grid.get_children():
		child.queue_free()
	if _spellbook == null or _ability_db == null:
		return
	var ids: Array = _spellbook.learned_ranks.keys()
	ids.sort()
	for ability_id in ids:
		var rank := int(_spellbook.learned_ranks.get(ability_id, 0))
		if rank <= 0:
			continue
		var def := _ability_db.get_ability(String(ability_id))
		if def == null:
			continue
		if not _passes_filter(def):
			continue
		var item := SPELL_LIST_ITEM_SCENE.instantiate()
		spells_grid.add_child(item)
		_apply_item_width(item)
		item.set_data(def, rank)
		item.set_selected(String(ability_id) == _selected_ability_id)
		item.name_clicked.connect(_on_spell_name_clicked)
		item.icon_clicked.connect(_on_spell_icon_clicked)

	# Keep selection consistent with current filter.
	if _selected_ability_id != "":
		var selected_visible: bool = false
		for child in spells_grid.get_children():
			if "ability_id" in child and String(child.ability_id) == _selected_ability_id:
				selected_visible = true
				break
		if not selected_visible:
			_clear_selected_ability()

	call_deferred("_apply_spell_grid_item_widths")

func _refresh_loadout() -> void:
	if loadout_pad != null and _spellbook != null and _ability_db != null:
		loadout_pad.refresh_icons(_spellbook, _ability_db)

func _on_spell_name_clicked(ability_id: String) -> void:
	if ability_id == "":
		return
	if _tooltip != null and _tooltip.visible and _tooltip_ability_id == ability_id:
		_hide_tooltip()
		return
	_show_tooltip_for(ability_id)

func _on_spell_icon_clicked(ability_id: String) -> void:
	if ability_id == "":
		return
	if not _can_select_for_install(ability_id):
		return
	_selected_ability_id = ability_id
	for child in spells_grid.get_children():
		if child.has_method("set_selected"):
			child.set_selected(child.ability_id == ability_id)
	_update_assignment_visuals()

func _can_select_for_install(ability_id: String) -> bool:
	if _ability_db == null:
		return false
	var def := _ability_db.get_ability(ability_id)
	if def == null:
		return false
	var t := String(def.ability_type)
	return t != "aura" and t != "stance" and t != "buff" and t != "passive"

func _show_tooltip_for(ability_id: String) -> void:
	_ensure_tooltip_ref()
	if _tooltip == null or _spellbook == null:
		return
	var rank := int(_spellbook.learned_ranks.get(ability_id, 1))
	var pos := get_viewport().get_mouse_position()
	_tooltip.show_for(ability_id, max(1, rank), pos)
	_tooltip_ability_id = ability_id

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.hide_tooltip()
	_tooltip_ability_id = ""

func _on_slot_pressed(slot_index: int) -> void:
	if _spellbook == null:
		return
	if _selected_ability_id == "":
		return
	_spellbook.assign_ability_to_slot(_selected_ability_id, slot_index)
	_clear_selected_ability()
	_refresh_loadout()

func _clear_selected_ability() -> void:
	_selected_ability_id = ""
	for child in spells_grid.get_children():
		if child.has_method("set_selected"):
			child.set_selected(false)
	_update_assignment_visuals()

func _update_assignment_visuals() -> void:
	if loadout_pad != null and loadout_pad.has_method("set_assignment_mode"):
		loadout_pad.call("set_assignment_mode", _selected_ability_id != "")

func _on_filter_selected(index: int) -> void:
	_filter_index = index
	_refresh_list()

func _passes_filter(def: AbilityDefinition) -> bool:
	if def == null:
		return false
	var t: String = String(def.ability_type)
	match _filter_index:
		1: # Активные
			return t != "aura" and t != "stance" and t != "buff" and t != "passive"
		2: # Ауры/бафы
			return t == "aura" or t == "stance" or t == "buff" or t == "passive"
		_:
			return true

func _ensure_tooltip_ref() -> void:
	if _tooltip == null or not is_instance_valid(_tooltip):
		_tooltip = get_tree().get_first_node_in_group("ability_tooltip_singleton") as AbilityTooltip

func _apply_spell_grid_item_widths() -> void:
	if spells_grid == null:
		return
	for child in spells_grid.get_children():
		_apply_item_width(child)

func _apply_item_width(item: Control) -> void:
	if item == null or spells_grid == null:
		return
	var total_w: float = spells_grid.size.x
	if total_w <= 1.0 and spells_grid.get_parent() is Control:
		total_w = (spells_grid.get_parent() as Control).size.x
	item.custom_minimum_size.x = max(120, int(total_w) - 5)
