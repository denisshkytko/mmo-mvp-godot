extends CanvasLayer
class_name BuffsAuraHUD

const DEFAULT_FLYOUT_SLOTS := 3
const FLYOUT_MARGIN := 8.0
const FLYOUT_SPACING := 6.0
const ARROW_MARGIN := 6.0
const EXPANDED_RIGHT_OVERFLOW := -5.0
const TOGGLE_PANEL_GAP := 1.0

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
var _arrow_buttons: Array[Button] = []
var _arrow_home_pos: Array[Vector2] = []
var _primary_slot_abilities: Array[String] = []
var _flyout_slot_abilities: Array[Array] = []
var _arrow_up_text: String = "▲"
var _arrow_down_text: String = "▼"

func _ready() -> void:
	if toggle_button != null and not toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.connect(_on_toggle_pressed)
	if flyouts_layer != null:
		flyouts_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_slots()
	_create_flyouts()
	await get_tree().process_frame
	_cache_layout()
	_set_expanded(false, true)

func _setup_slots() -> void:
	_primary_slots.clear()
	_arrow_buttons.clear()
	_arrow_home_pos.clear()
	for i in range(5):
		var container := slot_row.get_node_or_null("SlotContainer%d" % i) as Control
		if container == null:
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
			slot_button.pressed.connect(_on_primary_slot_pressed.bind(i))
		if arrow_button != null:
			arrow_button.pressed.connect(_on_arrow_pressed.bind(i))
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
		var sub_arr: Array[String] = []
		for j in range(DEFAULT_FLYOUT_SLOTS):
			sub_arr.append("")
		_flyout_slot_abilities.append(sub_arr)
	print_debug("BuffsAuraHUD: created flyouts", _flyouts.size())

func _cache_layout() -> void:
	_collapsed_panel_pos = panel.position
	_collapsed_toggle_pos = toggle_button.position

func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	toggle_button.text = "▶" if _expanded else "◀"
	var shift_x := panel.size.x - toggle_button.size.x
	var final_panel_pos := _collapsed_panel_pos + Vector2(-shift_x + EXPANDED_RIGHT_OVERFLOW, 0.0) if _expanded else _collapsed_panel_pos
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
	if slot_index >= 2:
		return
	_toggle_flyout(slot_index)

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
	print_debug("flyout subslot pressed", slot_index, sub_index)

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
	if slot_index < _arrow_home_pos.size():
		arrow_button.position = _arrow_home_pos[slot_index]
	arrow_button.text = _arrow_up_text
