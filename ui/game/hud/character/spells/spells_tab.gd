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
var _flow_router: Node = null
var _db_ready: bool = false
var _player_ready: bool = false

func _ready() -> void:
	if filter_option != null and filter_option.item_count == 0:
		filter_option.add_item("Все")
		filter_option.add_item("Активные")
		filter_option.add_item("Ауры/бафы")
		filter_option.select(0)

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

	_tooltip = get_tree().get_first_node_in_group("ability_tooltip_singleton") as AbilityTooltip
	if loadout_pad != null and loadout_pad.has_signal("slot_pressed") and not loadout_pad.slot_pressed.is_connected(_on_slot_pressed):
		loadout_pad.slot_pressed.connect(_on_slot_pressed)

	var existing_player := get_tree().get_first_node_in_group("player") as Player
	if existing_player != null:
		_on_player_spawned(existing_player, null)

	_try_refresh()

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
		var item := SPELL_LIST_ITEM_SCENE.instantiate()
		spells_grid.add_child(item)
		item.set_data(def, rank)
		item.set_selected(String(ability_id) == _selected_ability_id)
		item.clicked.connect(_on_spell_clicked)

func _refresh_loadout() -> void:
	if loadout_pad != null and _spellbook != null and _ability_db != null:
		loadout_pad.refresh_icons(_spellbook, _ability_db)

func _on_spell_clicked(ability_id: String) -> void:
	if ability_id == "":
		return
	_selected_ability_id = ability_id
	for child in spells_grid.get_children():
		if child.has_method("set_selected"):
			child.set_selected(child.ability_id == ability_id)
	_show_tooltip_for(ability_id)

func _show_tooltip_for(ability_id: String) -> void:
	if _tooltip == null or _spellbook == null:
		return
	var rank := int(_spellbook.learned_ranks.get(ability_id, 1))
	var pos := get_viewport().get_mouse_position()
	_tooltip.show_for(ability_id, max(1, rank), pos)

func _on_slot_pressed(slot_index: int) -> void:
	if _spellbook == null:
		return
	if _selected_ability_id == "":
		return
	_spellbook.assign_ability_to_slot(_selected_ability_id, slot_index)
	_refresh_loadout()
