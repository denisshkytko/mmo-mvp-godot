extends CanvasLayer
class_name BuffsAuraHUD

@onready var panel: Panel = $Root/Panel
@onready var slot_row: HBoxContainer = $Root/Panel/SlotRow
@onready var toggle_button: Button = $Root/ToggleButton

var _expanded: bool = false
var _collapsed_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if toggle_button != null and not toggle_button.pressed.is_connected(_on_toggle_pressed):
		toggle_button.pressed.connect(_on_toggle_pressed)
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

func _get_slot_button(slot_index: int) -> TextureButton:
	var name := "Slot%d" % slot_index
	return slot_row.get_node_or_null(name) as TextureButton
