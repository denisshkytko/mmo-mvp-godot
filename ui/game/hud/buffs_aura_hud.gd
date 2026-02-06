extends CanvasLayer
class_name BuffsAuraHUD

const DEFAULT_EXPANDER_SLOTS := 3

@onready var panel: Panel = $Root/Panel
@onready var slot_row: HBoxContainer = $Root/Panel/SlotRow
@onready var toggle_button: Button = $Root/ToggleButton

var _expanded: bool = false
var _collapsed_pos: Vector2 = Vector2.ZERO
var _expanders: Dictionary = {}

func _ready() -> void:
	if toggle_button != null and not toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.connect(_on_toggle_pressed)
	_setup_expanders()
	await get_tree().process_frame
	_cache_layout()
	_set_expanded(false, true)

func _cache_layout() -> void:
	panel.size = slot_row.size
	_collapsed_pos = toggle_button.position

func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	toggle_button.text = "◀" if _expanded else "▶"
	var shift_x := panel.size.x - toggle_button.size.x
	var final_panel_pos := _collapsed_pos + Vector2(-shift_x, 0.0) if _expanded else _collapsed_pos
	var final_toggle_pos := _collapsed_pos + Vector2(-shift_x, 0.0) if _expanded else _collapsed_pos
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

func set_slot_icon(slot_index: int, texture: Texture2D) -> void:
	var slot := _get_slot_button(slot_index)
	if slot == null:
		return
	var icon := slot.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = texture

func set_expander_slot_count(slot_index: int, count: int) -> void:
	var data: Dictionary = _expanders.get(slot_index, {}) as Dictionary
	if data.is_empty():
		return
	var slots: Array = data.get("slots", []) as Array
	for i in range(slots.size()):
		var btn := slots[i] as TextureButton
		if btn != null:
			btn.visible = i < count
	data["slot_count"] = count
	_expanders[slot_index] = data

func _get_slot_button(slot_index: int) -> TextureButton:
	var data: Dictionary = _expanders.get(slot_index, {}) as Dictionary
	if data.is_empty():
		return null
	return data.get("slot_button", null) as TextureButton

func _setup_expanders() -> void:
	for slot_index in range(5):
		var container := slot_row.get_node_or_null("SlotContainer%d" % slot_index) as Control
		if container == null:
			continue
		var slot_button := container.get_node_or_null("SlotButton") as TextureButton
		if slot_button == null:
			slot_button = container.get_node_or_null("SlotRow/SlotButton") as TextureButton
		var expander := container.get_node_or_null("Expander") as Control
		var expander_slots := container.get_node_or_null("Expander/Slots") as HBoxContainer
		var arrow_button := container.get_node_or_null("ArrowButton") as Button
		if arrow_button == null:
			arrow_button = container.get_node_or_null("SlotRow/ArrowButton") as Button
		var slots: Array = []
		if expander_slots != null:
			for child in expander_slots.get_children():
				if child is TextureButton:
					slots.append(child)
		if slot_button != null and slot_index < 2:
			if not slot_button.pressed.is_connected(_on_slot_toggle):
				slot_button.pressed.connect(_on_slot_toggle.bind(slot_index))
		if arrow_button != null and slot_index >= 2:
			if not arrow_button.pressed.is_connected(_on_slot_toggle):
				arrow_button.pressed.connect(_on_slot_toggle.bind(slot_index))
		if expander != null:
			expander.visible = false
		_expanders[slot_index] = {
			"container": container,
			"slot_button": slot_button,
			"arrow_button": arrow_button,
			"expander": expander,
			"slots": slots,
			"slot_count": DEFAULT_EXPANDER_SLOTS,
		}
		set_expander_slot_count(slot_index, DEFAULT_EXPANDER_SLOTS)

func _on_slot_toggle(slot_index: int) -> void:
	var data: Dictionary = _expanders.get(slot_index, {}) as Dictionary
	if data.is_empty():
		return
	var expander := data.get("expander", null) as Control
	if expander == null:
		return
	expander.visible = not expander.visible
