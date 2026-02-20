extends CanvasLayer
class_name BuffsAuraHUD

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")
const FLYOUT_MARGIN := 8.0
const FLYOUT_SPACING := 6.0
const ARROW_MARGIN := 6.0
const TOGGLE_PANEL_GAP := 1.0
const REQUIRED_SIDE_PADDING := 5.0

@export var flyout_scene: PackedScene = preload("res://ui/game/hud/buffs_aura/buff_aura_flyout.tscn")

@onready var panel: Panel = $Root/Panel
@onready var slot_row: HBoxContainer = $Root/Panel/SlotRow
@onready var toggle_button: Button = $Root/ToggleButton
@onready var flyouts_layer: Control = $Root/FlyoutsLayer

var _expanded: bool = false
var _collapsed_panel_pos: Vector2 = Vector2.ZERO
var _collapsed_toggle_pos: Vector2 = Vector2.ZERO
var _flyouts: Array[Control] = []
var _open_flyout_slot: int = -1
var _primary_slots: Array[TextureButton] = []
var _slot_containers: Array[Control] = []
var _arrow_buttons: Array[Button] = []
var _arrow_home_pos: Array[Vector2] = []
var _inter_slot_gaps: Array[Control] = []
var _primary_slot_abilities: Array[String] = []
var _flyout_slot_abilities: Array[Array] = []
var _arrow_up_text: String = "▲"
var _arrow_down_text: String = "▼"
var _player: Player = null
var _spellbook: PlayerSpellbook = null
var _ability_db: AbilityDatabase = null
var _flow_router: Node = null
var _db_ready: bool = false
var _player_ready: bool = false
var _slot_row_side_padding: float = 0.0
var _slot_row_separation: float = 0.0

func _ready() -> void:
	if toggle_button != null and not toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.connect(_on_toggle_pressed)
	_setup_slots()
	_create_flyouts()

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

	var existing_player := get_tree().get_first_node_in_group("player") as Player
	if existing_player != null:
		_on_player_spawned(existing_player, null)

	await get_tree().process_frame
	_cache_layout()
	_set_expanded(false, true)
	_try_refresh()

func _setup_slots() -> void:
	_primary_slots.clear()
	_slot_containers.clear()
	_arrow_buttons.clear()
	_arrow_home_pos.clear()
	_inter_slot_gaps = [
		slot_row.get_node_or_null("GapLarge1") as Control,
		slot_row.get_node_or_null("GapLarge2") as Control
	]
	for i in range(5):
		var container := slot_row.get_node_or_null("SlotContainer%d" % i) as Control
		if container == null:
			_slot_containers.append(null)
			_primary_slots.append(null)
			_arrow_buttons.append(null)
			_arrow_home_pos.append(Vector2.ZERO)
			continue
		var slot_button := container.get_node_or_null("SlotButton") as TextureButton
		if slot_button == null:
			slot_button = container.get_node_or_null("SlotRow/SlotButton") as TextureButton
		var arrow_button := container.get_node_or_null("ArrowButton") as Button
		if arrow_button == null:
			arrow_button = container.get_node_or_null("SlotRow/ArrowButton") as Button
		if slot_button != null:
			slot_button.ignore_texture_size = true
			slot_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			var placeholder := slot_button.get_node_or_null("Icon") as Control
			if placeholder != null:
				placeholder.visible = false
			slot_button.pressed.connect(_on_primary_slot_pressed.bind(i))
		if arrow_button != null:
			arrow_button.pressed.connect(_on_arrow_pressed.bind(i))
		_slot_containers.append(container)
		_primary_slots.append(slot_button)
		_arrow_buttons.append(arrow_button)
		if arrow_button != null:
			_arrow_home_pos.append(arrow_button.position)
			arrow_button.text = _arrow_up_text
		else:
			_arrow_home_pos.append(Vector2.ZERO)

func _create_flyouts() -> void:
	_flyouts.clear()
	_primary_slot_abilities = ["", "", "", "", ""]
	_flyout_slot_abilities = []
	if flyout_scene == null:
		push_error("BuffsAuraHUD: flyout_scene is missing or invalid.")
		return
	var ref_size := _get_reference_slot_size()
	for i in range(5):
		var flyout := flyout_scene.instantiate() as Control
		flyouts_layer.add_child(flyout)
		flyout.visible = false
		if flyout is BuffAuraFlyout:
			var typed := flyout as BuffAuraFlyout
			typed.slot_index = i
			typed.subslot_pressed.connect(_on_flyout_subslot_pressed)
			typed.apply_reference_size(ref_size, FLYOUT_SPACING)
		_flyouts.append(flyout)
		_flyout_slot_abilities.append([])
	print_debug("BuffsAuraHUD: created flyouts", _flyouts.size())

func _cache_layout() -> void:
	_collapsed_panel_pos = panel.position
	_collapsed_toggle_pos = toggle_button.position
	var left_padding := slot_row.position.x
	var right_padding := panel.size.x - (slot_row.position.x + slot_row.size.x)
	_slot_row_side_padding = max(0.0, left_padding + right_padding)
	_slot_row_side_padding = max(_slot_row_side_padding, REQUIRED_SIDE_PADDING * 2.0)
	_slot_row_separation = float(slot_row.get_theme_constant("separation"))

func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	toggle_button.text = "▶" if _expanded else "◀"
	if not _expanded and _open_flyout_slot != -1:
		_close_flyout(_open_flyout_slot)
		_open_flyout_slot = -1
	var shift_x := panel.size.x - toggle_button.size.x
	var final_panel_pos := _collapsed_panel_pos + Vector2(-shift_x, 0.0) if _expanded else _collapsed_panel_pos
	var final_toggle_pos := _collapsed_toggle_pos
	if _expanded:
		final_toggle_pos = Vector2(final_panel_pos.x - toggle_button.size.x - TOGGLE_PANEL_GAP, _collapsed_toggle_pos.y)
	if _expanded:
		panel.visible = true
	if immediate:
		panel.position = final_panel_pos
		toggle_button.position = final_toggle_pos
		if not _expanded:
			panel.visible = false
		return
	var tween := create_tween()
	tween.tween_property(panel, "position", final_panel_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(toggle_button, "position", final_toggle_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not _expanded:
		tween.tween_callback(func() -> void: panel.visible = false)

func _on_toggle_pressed() -> void:
	_set_expanded(not _expanded, false)

func _on_primary_slot_pressed(slot_index: int) -> void:
	if slot_index < 2:
		_toggle_flyout(slot_index)
		return
	_cast_buff_from_slot(slot_index)

func _on_arrow_pressed(slot_index: int) -> void:
	if slot_index < 2:
		return
	_toggle_flyout(slot_index)

func _toggle_flyout(slot_index: int) -> void:
	print_debug("BuffsAuraHUD: toggle flyout", slot_index, "open:", _open_flyout_slot)
	if slot_index < 0 or slot_index >= _flyouts.size():
		return
	if _open_flyout_slot == slot_index:
		_close_flyout(slot_index)
		_open_flyout_slot = -1
		return
	if _open_flyout_slot != -1:
		_close_flyout(_open_flyout_slot)
	_open_flyout(slot_index)
	_open_flyout_slot = slot_index

func _open_flyout(slot_index: int) -> void:
	var flyout := _flyouts[slot_index]
	var slot_button := _primary_slots[slot_index]
	if flyout == null or slot_button == null:
		return
	flyout.visible = true
	await get_tree().process_frame
	var btn_pos := slot_button.global_position
	var btn_size := _get_control_size(slot_button)
	var fly_size := flyout.size
	var x := btn_pos.x + (btn_size.x - fly_size.x) * 0.5
	var y := btn_pos.y - fly_size.y - FLYOUT_MARGIN
	var vp: Vector2 = get_viewport().get_visible_rect().size
	x = clamp(x, FLYOUT_MARGIN, vp.x - fly_size.x - FLYOUT_MARGIN)
	y = clamp(y, FLYOUT_MARGIN, vp.y - fly_size.y - FLYOUT_MARGIN)
	flyout.global_position = Vector2(x, y)
	print_debug("BuffsAuraHUD: open flyout", slot_index, "btn:", btn_pos, "size:", fly_size)
	_move_arrow_to_flyout(slot_index, flyout, slot_button)

func _close_flyout(slot_index: int) -> void:
	var flyout := _flyouts[slot_index]
	if flyout == null:
		return
	flyout.visible = false
	_reset_arrow(slot_index)

func _on_flyout_subslot_pressed(slot_index: int, sub_index: int) -> void:
	if slot_index < 0 or slot_index >= _flyout_slot_abilities.size():
		return
	var sub_arr: Array = _flyout_slot_abilities[slot_index]
	if sub_index < 0 or sub_index >= sub_arr.size():
		return
	var ability_id: String = String(sub_arr[sub_index])
	if ability_id == "" or _spellbook == null:
		return
	if slot_index == 0:
		_spellbook.assign_aura_active(ability_id)
	elif slot_index == 1:
		_spellbook.assign_stance_active(ability_id)
	else:
		_spellbook.assign_buff_to_slot(ability_id, slot_index - 2)
	_close_flyout(slot_index)
	_open_flyout_slot = -1

func set_primary_slot_ability(slot_index: int, ability_id: String) -> void:
	if slot_index < 0 or slot_index >= _primary_slot_abilities.size():
		return
	_primary_slot_abilities[slot_index] = ability_id

func set_flyout_slot_ability(slot_index: int, sub_index: int, ability_id: String) -> void:
	if slot_index < 0 or slot_index >= _flyout_slot_abilities.size():
		return
	var sub_arr: Array = _flyout_slot_abilities[slot_index]
	if sub_index < 0 or sub_index >= sub_arr.size():
		return
	sub_arr[sub_index] = ability_id
	_flyout_slot_abilities[slot_index] = sub_arr

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
	_refresh_from_spellbook()

func _refresh_from_spellbook() -> void:
	if _spellbook == null or _ability_db == null:
		return
	_set_primary_slot(0, _spellbook.aura_active)
	_set_primary_slot(1, _spellbook.stance_active)
	var buff_slot_count := _spellbook.buff_slots.size()
	for i in range(buff_slot_count):
		var ability_id := ""
		if i < _spellbook.buff_slots.size():
			ability_id = _spellbook.buff_slots[i]
		_set_primary_slot(i + 2, ability_id)
	for i in range(buff_slot_count, 3):
		_set_primary_slot(i + 2, "")

	var aura_candidates := _spellbook.get_learned_by_type("aura")
	if _spellbook.aura_active != "" and aura_candidates.has(_spellbook.aura_active):
		aura_candidates.erase(_spellbook.aura_active)
	var stance_candidates := _spellbook.get_learned_by_type("stance")
	if _spellbook.stance_active != "" and stance_candidates.has(_spellbook.stance_active):
		stance_candidates.erase(_spellbook.stance_active)
	var buff_candidates := _spellbook.get_buff_candidates_for_flyout()

	_set_flyout_entries(0, aura_candidates)
	_set_flyout_entries(1, stance_candidates)
	for i in range(buff_slot_count):
		_set_flyout_entries(i + 2, buff_candidates)
	for i in range(buff_slot_count, 3):
		_set_flyout_entries(i + 2, [])

	_set_arrow_visible(0, aura_candidates.size() > 0)
	_set_arrow_visible(1, stance_candidates.size() > 0)
	for i in range(buff_slot_count):
		_set_arrow_visible(i + 2, buff_candidates.size() > 0)
	for i in range(buff_slot_count, 3):
		_set_arrow_visible(i + 2, false)

	var slot_visible: Array[bool] = []
	for i in range(_slot_containers.size()):
		slot_visible.append(false)

	if slot_visible.size() > 0:
		slot_visible[0] = _spellbook.aura_active != "" or aura_candidates.size() > 0
	if slot_visible.size() > 1:
		slot_visible[1] = _spellbook.stance_active != "" or stance_candidates.size() > 0
	for i in range(2, slot_visible.size()):
		var buff_idx := i - 2
		if buff_idx >= buff_slot_count:
			slot_visible[i] = false
			continue
		var assigned_ability := ""
		if buff_idx < _spellbook.buff_slots.size():
			assigned_ability = _spellbook.buff_slots[buff_idx]
		slot_visible[i] = assigned_ability != "" or buff_candidates.size() > 0

	_apply_slot_layout_visibility(slot_visible)

func _set_primary_slot(slot_index: int, ability_id: String) -> void:
	set_primary_slot_ability(slot_index, ability_id)
	if slot_index < 0 or slot_index >= _primary_slots.size():
		return
	var button := _primary_slots[slot_index]
	if button == null:
		return
	var icon: Texture2D = null
	if ability_id != "" and _ability_db != null:
		var def: AbilityDefinition = _ability_db.get_ability(ability_id)
		if def != null:
			icon = def.icon
	button.texture_normal = icon
	button.texture_pressed = icon

func _set_flyout_entries(slot_index: int, ability_ids: Array[String]) -> void:
	if slot_index < 0 or slot_index >= _flyouts.size():
		return
	var flyout := _flyouts[slot_index]
	if flyout is BuffAuraFlyout:
		var typed := flyout as BuffAuraFlyout
		typed.set_entries(ability_ids, _ability_db)
	_flyout_slot_abilities[slot_index] = ability_ids.duplicate()

func _set_arrow_visible(slot_index: int, visible_value: bool) -> void:
	if slot_index < 0 or slot_index >= _arrow_buttons.size():
		return
	var arrow_button := _arrow_buttons[slot_index]
	if arrow_button != null:
		arrow_button.visible = visible_value

func _apply_slot_layout_visibility(slot_visible: Array[bool]) -> void:
	for i in range(_slot_containers.size()):
		var container := _slot_containers[i]
		if container == null:
			continue
		var visible_value := i < slot_visible.size() and slot_visible[i]
		container.visible = visible_value
		if not visible_value and _open_flyout_slot == i:
			_close_flyout(i)
			_open_flyout_slot = -1

	for gap_idx in range(_inter_slot_gaps.size()):
		var gap := _inter_slot_gaps[gap_idx]
		if gap == null:
			continue
		var left_visible := gap_idx < slot_visible.size() and slot_visible[gap_idx]
		var right_visible := (gap_idx + 1) < slot_visible.size() and slot_visible[gap_idx + 1]
		gap.visible = left_visible and right_visible

	var row_width := _calculate_visible_row_width(slot_visible)
	var panel_width := row_width + _slot_row_side_padding
	var panel_min := panel.custom_minimum_size
	panel_min.x = panel_width
	panel.custom_minimum_size = panel_min
	var row_min := slot_row.custom_minimum_size
	row_min.x = row_width
	slot_row.custom_minimum_size = row_min
	panel.size.x = panel_width
	if _expanded:
		_set_expanded(true, true)

func _calculate_visible_row_width(slot_visible: Array[bool]) -> float:
	var width := 0.0
	var visible_count := 0
	for i in range(_slot_containers.size()):
		if i >= slot_visible.size() or not slot_visible[i]:
			continue
		var container := _slot_containers[i]
		if container == null:
			continue
		var slot_width := _get_control_size(container).x
		if slot_width <= 0.0:
			slot_width = container.custom_minimum_size.x
		width += slot_width
		visible_count += 1

	for gap_idx in range(_inter_slot_gaps.size()):
		var gap := _inter_slot_gaps[gap_idx]
		if gap == null or not gap.visible:
			continue
		width += gap.custom_minimum_size.x

	if visible_count > 1:
		width += _slot_row_separation * float(visible_count - 1)

	if width <= 0.0:
		width = _get_reference_slot_size().x
	return width

func _cast_buff_from_slot(slot_index: int) -> void:
	if _player == null or _spellbook == null:
		return
	var buff_idx := slot_index - 2
	if buff_idx < 0 or buff_idx >= _spellbook.buff_slots.size():
		return
	var ability_id: String = _spellbook.buff_slots[buff_idx]
	if ability_id == "":
		return
	var target: Node = null
	var gm := NODE_CACHE.get_game_manager(get_tree())
	if gm != null and gm.has_method("get_target"):
		target = gm.call("get_target")
	if target == null:
		target = _player
	if _player.c_ability_caster != null:
		_player.c_ability_caster.try_cast(ability_id, target)

func _get_reference_slot_size() -> Vector2:
	for slot_button in _primary_slots:
		if slot_button != null:
			var size := _get_control_size(slot_button)
			if size != Vector2.ZERO:
				return size
	return Vector2(34.0, 34.0)

func _get_control_size(control: Control) -> Vector2:
	if control == null:
		return Vector2.ZERO
	var size := control.size
	if size == Vector2.ZERO:
		size = control.get_combined_minimum_size()
	if size == Vector2.ZERO:
		size = control.custom_minimum_size
	return size

func _move_arrow_to_flyout(slot_index: int, flyout: Control, slot_button: Control) -> void:
	if slot_index < 2:
		return
	if slot_index >= _arrow_buttons.size():
		return
	var arrow_button := _arrow_buttons[slot_index]
	if arrow_button == null:
		return
	arrow_button.top_level = true
	var arrow_size := _get_control_size(arrow_button)
	var btn_pos := slot_button.global_position
	var btn_size := _get_control_size(slot_button)
	var x := btn_pos.x + (btn_size.x - arrow_size.x) * 0.5
	var y := flyout.global_position.y - arrow_size.y - ARROW_MARGIN
	arrow_button.global_position = Vector2(x, y)
	arrow_button.text = _arrow_down_text

func _reset_arrow(slot_index: int) -> void:
	if slot_index < 2:
		return
	if slot_index >= _arrow_buttons.size():
		return
	var arrow_button := _arrow_buttons[slot_index]
	if arrow_button == null:
		return
	arrow_button.top_level = false
	if slot_index < _arrow_home_pos.size():
		arrow_button.position = _arrow_home_pos[slot_index]
	arrow_button.text = _arrow_up_text
