extends Control

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")
const SPELL_LIST_ITEM_SCENE := preload("res://ui/game/hud/character/spells/spell_list_item.tscn")

@onready var spells_grid: GridContainer = $SpellsVBox/SpellsPanelA/SpellsVBox/SpellsMargin/SpellsScroll/SpellsGrid
@onready var loadout_pad: Control = $SpellsVBox/SpellsPanelB/LoadoutMargin/LoadoutVBox/LoadoutPadRoot
@onready var filter_option: OptionButton = $SpellsVBox/SpellsPanelA/SpellsVBox/SpellFilterOption

var _player: Player = null
var _spellbook: PlayerSpellbook = null
var _ability_db: AbilityDatabase = null
var _tooltip: AbilityTooltip = null
var _selected_ability_id: String = ""

func _ready() -> void:
	_player = NODE_CACHE.get_player(get_tree()) as Player
	if filter_option != null and filter_option.item_count == 0:
		filter_option.add_item("Все")
		filter_option.add_item("Активные")
		filter_option.add_item("Ауры/бафы")
		filter_option.select(0)
	if _player != null:
		_spellbook = _player.c_spellbook
	_ability_db = get_node_or_null("/root/AbilityDB") as AbilityDatabase
	_tooltip = get_tree().get_first_node_in_group("ability_tooltip_singleton") as AbilityTooltip
	if _spellbook != null and not _spellbook.spellbook_changed.is_connected(_on_spellbook_changed):
		_spellbook.spellbook_changed.connect(_on_spellbook_changed)
	if loadout_pad != null and loadout_pad.has_signal("slot_pressed"):
		loadout_pad.connect("slot_pressed", _on_slot_pressed)
	_refresh_all()

func _on_spellbook_changed() -> void:
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
