extends CanvasLayer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/shared/tooltip_text_builder.gd")
signal hud_visibility_changed(is_open: bool)
@onready var panel: Control = $Root/Panel
@onready var gold_label: RichTextLabel = $Root/Panel/GoldLabel
@onready var content: Control = $Root/Panel/Content
@onready var grid_scroll_wrapper: Control = $Root/Panel/Content/GridScrollWrapper
@onready var grid_scroll: ScrollContainer = $Root/Panel/Content/GridScrollWrapper/GridScroll
@onready var grid: GridContainer = $Root/Panel/Content/GridScrollWrapper/GridScroll/Grid
@onready var bag_slots: Control = $Root/Panel/Content/BagSlots

@onready var settings_button_scene: Button = $Root/Panel/InvSettingsButton
@onready var settings_panel_scene: Panel = $Root/Panel/InvSettingsPanel
@onready var settings_title_label_scene: Label = $Root/Panel/InvSettingsPanel/Margin/VBox/GridTitle
@onready var settings_columns_label_scene: Label = $Root/Panel/InvSettingsPanel/Margin/VBox/ColumnsRow/ColumnsLabel
@onready var settings_minus_scene: Button = $Root/Panel/InvSettingsPanel/Margin/VBox/ColumnsRow/MinusButton
@onready var settings_value_scene: Label = $Root/Panel/InvSettingsPanel/Margin/VBox/ColumnsRow/ValueLabel
@onready var settings_plus_scene: Button = $Root/Panel/InvSettingsPanel/Margin/VBox/ColumnsRow/PlusButton
@onready var settings_sort_title_scene: Label = $Root/Panel/InvSettingsPanel/Margin/VBox/SortTitle
@onready var settings_sort_scene: Button = $Root/Panel/InvSettingsPanel/Margin/VBox/SortButton

@onready var bag_button: Button = get_node_or_null("BagButton")
@onready var bag_slot1: Button = $Root/Panel/Content/BagSlots/BagSlot1
@onready var bag_slot2: Button = $Root/Panel/Content/BagSlots/BagSlot2
@onready var bag_slot3: Button = $Root/Panel/Content/BagSlots/BagSlot3
@onready var bag_slot4: Button = $Root/Panel/Content/BagSlots/BagSlot4

@onready var bag_full_dialog: AcceptDialog = $Root/BagFullDialog

# Tooltip is defined in the scene (like LootHUD), not created dynamically.
@onready var tooltip_panel_scene: Panel = $Root/InvTooltip
@onready var tooltip_label_scene: RichTextLabel = $Root/InvTooltip/Margin/VBox/Text
@onready var tooltip_use_btn_scene: Button = $Root/InvTooltip/Margin/VBox/UseButton
@onready var tooltip_equip_btn_scene: Button = $Root/InvTooltip/Margin/VBox/EquipButton
@onready var tooltip_sell_btn_scene: Button = $Root/InvTooltip/Margin/VBox/SellButton
@onready var tooltip_quick_btn_scene: Button = $Root/InvTooltip/Margin/VBox/QuickSlotButton
@onready var tooltip_bag_btn_scene: Button = $Root/InvTooltip/Margin/VBox/BagButton
@onready var tooltip_close_btn_scene: Button = $Root/InvTooltip/CloseButton

var player: Node = null
var _is_open: bool = true
var _trade_open: bool = false

const HOLD_THRESHOLD_MS: int = 1000
var _slot_press_start_ms: int = 0
var _slot_press_index: int = -1
var _slot_press_pos: Vector2 = Vector2.ZERO

var _bag_press_start_ms: int = 0
var _bag_press_index: int = -1
var _bag_press_pos: Vector2 = Vector2.ZERO

# Tooltip (fixed width, grows in height; supports rich color for required level)
var _tooltip_panel: Panel = null
var _tooltip_label: RichTextLabel = null
var _tooltip_use_btn: Button = null
var _tooltip_equip_btn: Button = null
var _tooltip_sell_btn: Button = null
var _tooltip_quick_btn: Button = null
var _tooltip_bag_btn: Button = null
var _tooltip_close_btn: Button = null
var _tooltip_for_slot: int = -1
var _tooltip_for_bag_slot: int = -1

# Small center toast ("hp full" / "mana full")
var _toast_label: Label = null

# Split dialog
@onready var split_dialog: Panel = $Root/SplitDialog
@onready var split_title: Label = $Root/SplitDialog/SplitTitle
@onready var split_slider: HSlider = $Root/SplitDialog/SplitSlider
@onready var split_amount: Label = $Root/SplitDialog/SplitAmount
@onready var split_ok: Button = $Root/SplitDialog/SplitOk
@onready var split_cancel: Button = $Root/SplitDialog/SplitCancel
var _split_source_slot: int = -1

# Settings UI (columns/rows + sort)
var _settings_button: Button = null
var _settings_panel: Panel = null
var _settings_title_label: Label = null
var _settings_columns_label: Label = null
var _settings_minus: Button = null
var _settings_value: Label = null
var _settings_plus: Button = null
var _settings_sort_title: Label = null
var _settings_sort: Button = null

var _grid_columns: int = 4 # default layout for inventory

const _GRID_CFG_PATH := "user://inventory_grid.cfg"
const _GRID_CFG_SECTION := "inventory_hud"
const _GRID_CFG_KEY_COLUMNS := "grid_columns"

# Quick slots (5) - references to inventory slot indices
var _quick_bar: HBoxContainer = null
var _quick_buttons: Array[Button] = []
var _quick_refs: Array[String] = ["", "", "", "", ""]  # item_id per quick slot
var _quick_slots_syncing: bool = false


# Lightweight refresh while inventory is open (so looting updates immediately).
var _refresh_accum: float = 0.0

# Layout recalculation should only happen when grid geometry changes (startup,
# apply settings, or bag slots changing total slot count). Regular item moves
# should not trigger any resizing/re-anchoring.
var _layout_dirty: bool = true
var _last_total_slots: int = -1
var _last_applied_columns: int = -1
var _refresh_in_progress: bool = false
var _last_bag_slots_hash: int = 0
var _refresh_requested: bool = false
var _inventory_signal_source: Object = null

var _rebuild_in_progress: bool = false
var _rebuild_requested: bool = false

# Layout anchor: keep panel growing towards screen center (up + left) from a stable bottom-right point
var _panel_br_anchor: Vector2 = Vector2.ZERO
var _panel_anchor_valid: bool = false

# Icon cache for slot buttons
var _icon_cache: Dictionary = {} # path -> Texture2D
var _tooltip_layer: CanvasLayer = null
var _dialog_layer: CanvasLayer = null
var _error_layer: CanvasLayer = null
var _initial_layout_done: bool = false
var _initial_layout_pending: bool = false

func _trf(key: String, params: Dictionary = {}) -> String:
	return tr(key).format(params)

func _ready() -> void:
	add_to_group("inventory_ui")
	# default to closed in actual gameplay; keep current behavior
	_is_open = panel.visible
	emit_signal("hud_visibility_changed", _is_open)
	if gold_label != null:
		gold_label.bbcode_enabled = true
		gold_label.fit_content = true
		gold_label.scroll_active = false

	if split_title != null:
		split_title.text = tr("ui.inventory.split")
	if split_ok != null:
		split_ok.text = tr("ui.common.accept")
	if split_cancel != null:
		split_cancel.text = tr("ui.common.cancel")
	if bag_full_dialog != null:
		bag_full_dialog.title = tr("ui.common.inventory_title")
		bag_full_dialog.dialog_text = tr("ui.common.bag_full")

	if bag_button != null:
		bag_button.pressed.connect(_on_bag_button_pressed)
	if grid_scroll_wrapper != null:
		grid_scroll_wrapper.layout_mode = 2
		grid_scroll_wrapper.set_anchors_preset(Control.PRESET_TOP_LEFT)
		grid_scroll_wrapper.anchor_left = 0
		grid_scroll_wrapper.anchor_top = 0
		grid_scroll_wrapper.anchor_right = 0
		grid_scroll_wrapper.anchor_bottom = 0
		grid_scroll_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid_scroll_wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid_scroll_wrapper.size_flags_stretch_ratio = 0.0
	if grid_scroll != null:
		grid_scroll.layout_mode = 2
		grid_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		grid_scroll.anchor_left = 0
		grid_scroll.anchor_top = 0
		grid_scroll.anchor_right = 1
		grid_scroll.anchor_bottom = 1
		grid_scroll.offset_left = 0
		grid_scroll.offset_top = 0
		grid_scroll.offset_right = 0
		grid_scroll.offset_bottom = 0
		grid_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid_scroll.size_flags_stretch_ratio = 0.0
		grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Bag equipment slots (visual order: top -> bottom).
	_get_bag_button_for_logical(0).gui_input.connect(_on_bag_slot_gui_input.bind(0))
	_get_bag_button_for_logical(1).gui_input.connect(_on_bag_slot_gui_input.bind(1))
	_get_bag_button_for_logical(2).gui_input.connect(_on_bag_slot_gui_input.bind(2))
	_get_bag_button_for_logical(3).gui_input.connect(_on_bag_slot_gui_input.bind(3))

	_ensure_support_ui()
	_style_inventory_tooltip()
	_hook_slot_panels()
	_auto_bind_player()
	_refresh_quick_bar_snapshot()
	_load_grid_columns()
	if content != null:
		var left_offset: float = content.offset_left
		var top_offset: float = content.offset_top
		content.offset_left = left_offset
		content.offset_top = top_offset
		content.offset_right = -10.0
		content.offset_bottom = -10.0
	# Capture the bottom-right anchor based on where you placed the panel in the scene.
	# This anchor will be used for all future resizes so the panel grows up+left.
	await get_tree().process_frame
	_panel_br_anchor = panel.position + panel.size
	_panel_anchor_valid = true

func set_player(p: Node) -> void:
	player = p
	_initial_layout_done = false
	_layout_dirty = true
	_last_applied_columns = -1
	_bind_inventory_signal()
	_refresh_quick_bar_snapshot()
	if _is_open:
		await _force_initial_layout()
		await _refresh()

func set_trade_open(state: bool) -> void:
	_trade_open = state

func hide_tooltip() -> void:
	_hide_tooltip()

func _auto_bind_player() -> void:
	# Try to bind automatically if caller didn't call set_player().
	if player != null and is_instance_valid(player):
		return
	# Prefer group-based lookup.
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() > 0:
		player = nodes[0]
		_bind_inventory_signal()
		return
	# Fallback by common node name.
	var root := get_tree().current_scene
	if root == null:
		return
	var p := root.find_child("Player", true, false)
	if p != null:
		player = p
		_bind_inventory_signal()

func _bind_inventory_signal() -> void:
	var source: Object = null
	if player != null and is_instance_valid(player):
		var inv_candidate: Variant = player.get("inventory")
		if inv_candidate != null and inv_candidate is Object and (inv_candidate as Object).has_signal("inventory_changed"):
			source = inv_candidate as Object
		if source == null and player.has_method("get_node_or_null"):
			var component := player.get_node_or_null("Components/Inventory")
			if component != null and component.has_signal("inventory_changed"):
				source = component
		if source == null:
			var component_alt: Variant = player.get("c_inv")
			if component_alt != null and component_alt is Object and (component_alt as Object).has_signal("inventory_changed"):
				source = component_alt as Object

	if _inventory_signal_source != null and _inventory_signal_source.has_signal("inventory_changed"):
		if _inventory_signal_source.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_signal_source.inventory_changed.disconnect(_on_inventory_changed)

	_inventory_signal_source = source
	if _inventory_signal_source != null:
		if not _inventory_signal_source.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_signal_source.inventory_changed.connect(_on_inventory_changed)
	_refresh_quick_bar_snapshot()

func _on_inventory_changed() -> void:
	_layout_dirty = true
	_refresh_requested = true
	if not _is_open:
		_refresh_quick_bar_snapshot()

func is_open() -> bool:
	return _is_open

func _is_player_ready() -> bool:
	return player != null and is_instance_valid(player) and player.has_method("get_inventory_snapshot")

func _get_total_slots_from_player_fallback() -> int:
	if not _is_player_ready():
		return 0
	var inv: Variant = player.get("inventory")
	if inv != null and inv.has_method("get_total_slot_count"):
		return int(inv.call("get_total_slot_count"))
	return Inventory.SLOT_COUNT

func _deferred_force_initial_layout() -> void:
	await _force_initial_layout()

func _set_grid_cells_visible(is_visible: bool) -> void:
	if grid == null:
		return
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		slot_panel.visible = is_visible

func _process(_delta: float) -> void:
	if _is_open and not _is_player_ready():
		_auto_bind_player()
	if _is_open and not _initial_layout_done and not _initial_layout_pending and _is_player_ready():
		call_deferred("_deferred_force_initial_layout")
	# While open, keep HUD in sync (so looting updates without requiring sort).
	if _is_open and _is_player_ready():
		if _refresh_requested:
			_refresh_requested = false
			await _refresh()
		_refresh_accum += _delta
		if _refresh_accum >= 0.12:
			_refresh_accum = 0.0
			var snap: Dictionary = player.get_inventory_snapshot()
			# Cooldowns tick even if inventory content didn't change.
			_update_visible_cooldowns(snap)

func _toggle_inventory() -> void:
	_set_open(not _is_open)

func _set_open(v: bool) -> void:
	_is_open = v
	panel.visible = v
	emit_signal("hud_visibility_changed", _is_open)
	if not v:
		_hide_tooltip()
		_hide_split()
		_hide_settings()
	else:
		# Two-frame stabilization so GridContainer lays out correctly on first open.
		await get_tree().process_frame
		_auto_bind_player()
		if not _is_player_ready():
			_initial_layout_done = false
			return
		if not _initial_layout_done:
			grid.visible = true
			grid.modulate.a = 0.0
			await _rebuild_layout("open")
			await get_tree().process_frame
			await _rebuild_layout("open_stabilize")
			await _refresh()
		else:
			await _refresh()

func _on_bag_button_pressed() -> void:
	_toggle_inventory()


func toggle_inventory() -> void:
	_toggle_inventory()

# --- Bag slots ---

func _get_bag_button_for_logical(logical_index: int) -> Button:
	# UI order (top->bottom): BagSlot1 BagSlot2 BagSlot3 BagSlot4
	match logical_index:
		0: return bag_slot1
		1: return bag_slot2
		2: return bag_slot3
		3: return bag_slot4
		_: return bag_slot1

func _on_bag_slot_gui_input(event: InputEvent, bag_index: int) -> void:
	if _is_settings_open():
		return
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_bag_press_start_ms = Time.get_ticks_msec()
			_bag_press_index = bag_index
			_bag_press_pos = mb.global_position
			return
		if _bag_press_index != bag_index:
			return
		if mb.global_position.distance_to(_bag_press_pos) > 1.0:
			_bag_press_index = -1
			return
		var held_ms := Time.get_ticks_msec() - _bag_press_start_ms
		_bag_press_index = -1
		if held_ms > HOLD_THRESHOLD_MS:
			return
		_show_tooltip_for_bag_slot(bag_index, mb.global_position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_bag_press_start_ms = Time.get_ticks_msec()
			_bag_press_index = bag_index
			_bag_press_pos = st.position
			return
		if _bag_press_index != bag_index:
			return
		if st.position.distance_to(_bag_press_pos) > 1.0:
			_bag_press_index = -1
			return
		var held_ms2 := Time.get_ticks_msec() - _bag_press_start_ms
		_bag_press_index = -1
		if held_ms2 > HOLD_THRESHOLD_MS:
			return
		_show_tooltip_for_bag_slot(bag_index, st.position)

# --- Slot grid ---

func _ensure_grid_child_count(target: int) -> void:
	if target < 0:
		target = 0
	var current: int = grid.get_child_count()
	if current == 0:
		return

	var template: Panel = grid.get_child(0) as Panel
	if template == null:
		return

	while grid.get_child_count() < target:
		var clone: Panel = template.duplicate() as Panel
		# Remove duplicated connections/meta so we can hook with correct slot index.
		# IMPORTANT: our hook flag is "_hooked" (not "hooked").
		# If we don't remove it, only the template slot stays interactive.
		if clone.has_meta("_hooked"):
			clone.remove_meta("_hooked")
		# Disconnect any duplicated gui_input handlers.
		for conn in clone.gui_input.get_connections():
			if conn.has("callable"):
				clone.gui_input.disconnect(conn["callable"])
		grid.add_child(clone)

	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		slot_panel.visible = i < target
		_ensure_slot_visuals(slot_panel)

func _ensure_slot_visuals(slot_panel: Panel) -> void:
	# Ensure we have an Icon and a Count label inside the slot panel.
	var icon := slot_panel.get_node_or_null("Icon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(icon)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4

	var count_label := slot_panel.get_node_or_null("Count") as Label
	if count_label == null:
		count_label = Label.new()
		count_label.name = "Count"
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.clip_text = true
		slot_panel.add_child(count_label)
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		count_label.offset_left = 2
		count_label.offset_top = 2
		count_label.offset_right = -2
		count_label.offset_bottom = -2

	# Cooldown overlay (for consumables), similar to ability cooldown visuals.
	var cd := slot_panel.get_node_or_null("Cooldown") as ColorRect
	if cd == null:
		cd = ColorRect.new()
		cd.name = "Cooldown"
		cd.color = Color(0, 0, 0, 0.65)
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(cd)
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.offset_left = 0
		cd.offset_top = 0
		cd.offset_right = 0
		cd.offset_bottom = 0
		var cd_lbl := Label.new()
		cd_lbl.name = "CooldownText"
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.add_child(cd_lbl)
		cd_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd_lbl.offset_left = 0
		cd_lbl.offset_top = 0
		cd_lbl.offset_right = 0
		cd_lbl.offset_bottom = 0

	# Keep old Text label (template) unused; we stop writing into it.

func _hook_slot_panels() -> void:
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		if slot_panel.has_meta("_hooked"):
			continue
		slot_panel.set_meta("_hooked", true)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		slot_panel.gui_input.connect(_on_slot_gui_input.bind(i))

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if _is_settings_open():
		return
	if not _is_open:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_slot_press_start_ms = Time.get_ticks_msec()
				_slot_press_index = slot_index
				_slot_press_pos = mb.global_position
				return
			if _slot_press_index != slot_index:
				return
			if mb.global_position.distance_to(_slot_press_pos) > 1.0:
				_slot_press_index = -1
				return
			var held_ms := Time.get_ticks_msec() - _slot_press_start_ms
			_slot_press_index = -1
			if held_ms > HOLD_THRESHOLD_MS:
				_try_open_split(slot_index, mb.global_position)
				return
			_toggle_tooltip_for_slot(slot_index, mb.global_position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_slot_press_start_ms = Time.get_ticks_msec()
			_slot_press_index = slot_index
			_slot_press_pos = st.position
			return
		if _slot_press_index != slot_index:
			return
		if st.position.distance_to(_slot_press_pos) > 1.0:
			_slot_press_index = -1
			return
		var held_ms2 := Time.get_ticks_msec() - _slot_press_start_ms
		_slot_press_index = -1
		if held_ms2 > HOLD_THRESHOLD_MS:
			_try_open_split(slot_index, st.position)
			return
		_toggle_tooltip_for_slot(slot_index, st.position)

# --- Split logic ---

func _try_open_split(slot_index: int, global_pos: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return
	var v: Variant = slots[slot_index]
	if v == null or not (v is Dictionary):
		return
	var d: Dictionary = v as Dictionary
	var count: int = int(d.get("count", 0))
	if count <= 1:
		return
	_show_split(slot_index, count, global_pos)

func _show_split(slot_index: int, count: int, global_pos: Vector2) -> void:
	_split_source_slot = slot_index
	if split_slider != null:
		split_slider.min_value = 1
		split_slider.max_value = count
		split_slider.value = int(clamp(int(count / 2.0), 1, count))
	_update_split_label(count)
	if split_dialog != null:
		split_dialog.visible = true
		_position_panel_left_of_point(split_dialog, global_pos)
		_ensure_dialog_layer()

func _hide_split() -> void:
	if split_dialog != null:
		split_dialog.visible = false
	if split_slider != null:
		split_slider.value = split_slider.min_value
	if split_amount != null:
		split_amount.text = ""
	_split_source_slot = -1

func _on_split_value_changed(_v: float) -> void:
	if _split_source_slot == -1 or player == null:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _split_source_slot < 0 or _split_source_slot >= slots.size():
		return
	var d: Variant = slots[_split_source_slot]
	if d is Dictionary:
		_update_split_label(int((d as Dictionary).get("count", 0)))

func _update_split_label(total: int) -> void:
	var take: int = int(split_slider.value) if split_slider != null else 1
	if split_amount != null:
		split_amount.text = "%d / %d" % [take, total]

func _on_split_ok_pressed() -> void:
	if _split_source_slot == -1 or player == null:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _split_source_slot < 0 or _split_source_slot >= slots.size():
		return
	var v: Variant = slots[_split_source_slot]
	if v == null or not (v is Dictionary):
		return
	var d: Dictionary = v as Dictionary
	var total: int = int(d.get("count", 0))
	var take: int = int(split_slider.value) if split_slider != null else 1
	if take < 1 or take > total:
		_hide_split()
		return
	var free_idx := _find_first_free_slot(slots)
	if free_idx == -1:
		show_bag_full(tr("ui.common.bag_full"))
		_hide_split()
		return
	var id: String = String(d.get("id", ""))
	var remain: int = total - take
	if remain <= 0:
		slots[_split_source_slot] = null
	else:
		d["count"] = remain
		slots[_split_source_slot] = d
	slots[free_idx] = {"id": id, "count": take}
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)
	_hide_split()
	await _refresh()

func _on_split_cancel_pressed() -> void:
	_hide_split()

# --- Tooltip ---

func _toggle_tooltip_for_slot(slot_index: int, global_pos: Vector2) -> void:
	if _tooltip_for_slot == slot_index and _tooltip_panel != null and _tooltip_panel.visible:
		_hide_tooltip()
		return
	_show_tooltip_for_slot(slot_index, global_pos)

func _show_tooltip_for_slot(slot_index: int, global_pos: Vector2) -> void:
	_ensure_support_ui()
	if player == null or not is_instance_valid(player):
		_hide_tooltip()
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[slot_index]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return

	var id: String = String((v as Dictionary).get("id", ""))
	var count: int = int((v as Dictionary).get("count", 0))
	var db := get_node_or_null("/root/DataDB")
	if db != null and not db.is_ready:
		await db.initialized
	_tooltip_panel.visible = false
	# Collapse first so an empty background can never flash on first open.
	_tooltip_panel.custom_minimum_size = Vector2(_tooltip_panel.custom_minimum_size.x, 0)
	_tooltip_panel.size = Vector2(_tooltip_panel.size.x, 0)
	_tooltip_label.text = ""
	var text := _build_tooltip_text(id, count)
	if String(text).strip_edges().is_empty():
		_hide_tooltip()
		return
	_tooltip_label.text = text
	# "Use" button (inventory tooltip only)
	if _tooltip_use_btn != null:
		var is_cons := _is_consumable_item(id)
		_tooltip_use_btn.visible = is_cons
		if is_cons and player != null and player.has_method("is_consumable_on_cooldown"):
			var kind := _get_consumable_cd_kind_for_item(id)
			_tooltip_use_btn.disabled = bool(player.call("is_consumable_on_cooldown", kind))
		else:
			_tooltip_use_btn.disabled = false
	if _tooltip_equip_btn != null:
		var is_equippable := _is_equippable_item(id)
		_tooltip_equip_btn.visible = is_equippable
		_tooltip_equip_btn.disabled = false
	if _tooltip_sell_btn != null:
		_tooltip_sell_btn.visible = _trade_open
		_tooltip_sell_btn.disabled = false
	if _tooltip_quick_btn != null:
		var is_cons2 := _is_consumable_item(id)
		var quick_index := _get_quick_slot_index_for_item(id)
		_tooltip_quick_btn.visible = is_cons2
		_tooltip_quick_btn.text = tr("ui.inventory.quick_slot.remove") if quick_index != -1 else tr("ui.inventory.quick_slot.add")
		_tooltip_quick_btn.disabled = false
	if _tooltip_bag_btn != null:
		var is_bag := _is_bag_item(id)
		_tooltip_bag_btn.visible = is_bag
		_tooltip_bag_btn.text = tr("ui.inventory.bag.equip")
		_tooltip_bag_btn.disabled = false
	await _resize_tooltip_to_content()
	_tooltip_panel.visible = true
	_tooltip_for_slot = slot_index
	_tooltip_for_bag_slot = -1

	_position_tooltip_left_of_point(global_pos)

func _show_tooltip_for_bag_slot(bag_index: int, global_pos: Vector2) -> void:
	_ensure_support_ui()
	if player == null or not is_instance_valid(player):
		_hide_tooltip()
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var bags: Array = snap.get("bag_slots", [])
	if bag_index < 0 or bag_index >= bags.size():
		_hide_tooltip()
		return
	var v: Variant = bags[bag_index]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	var count: int = int((v as Dictionary).get("count", 1))
	_tooltip_panel.visible = false
	_tooltip_panel.custom_minimum_size = Vector2(_tooltip_panel.custom_minimum_size.x, 0)
	_tooltip_panel.size = Vector2(_tooltip_panel.size.x, 0)
	_tooltip_label.text = ""
	var text := _build_tooltip_text(id, count)
	if String(text).strip_edges().is_empty():
		_hide_tooltip()
		return
	_tooltip_label.text = text
	if _tooltip_use_btn != null:
		_tooltip_use_btn.visible = false
	if _tooltip_equip_btn != null:
		_tooltip_equip_btn.visible = false
	if _tooltip_sell_btn != null:
		_tooltip_sell_btn.visible = false
	if _tooltip_quick_btn != null:
		_tooltip_quick_btn.visible = false
	if _tooltip_bag_btn != null:
		_tooltip_bag_btn.visible = true
		_tooltip_bag_btn.text = tr("ui.inventory.quick_slot.remove")
		_tooltip_bag_btn.disabled = false
	await _resize_tooltip_to_content()
	_tooltip_panel.visible = true
	_tooltip_for_slot = -1
	_tooltip_for_bag_slot = bag_index
	_position_tooltip_left_of_point(global_pos)

func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
	_tooltip_for_slot = -1
	_tooltip_for_bag_slot = -1


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _tooltip_panel == null or not _tooltip_panel.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_hide_tooltip()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_hide_tooltip()


func _resize_tooltip_to_content() -> void:
	if _tooltip_panel == null or _tooltip_label == null:
		return
	var was_visible := _tooltip_panel.visible
	var prev_modulate := _tooltip_panel.modulate
	_tooltip_panel.visible = true
	_tooltip_panel.modulate = Color(prev_modulate.r, prev_modulate.g, prev_modulate.b, 0.0)
	# Align layout sizing with LootHUD so the first show measures correctly.
	var width: float = 360.0
	_tooltip_panel.size = Vector2(width, 10)
	_tooltip_panel.custom_minimum_size = Vector2(width, 0)
	_tooltip_label.custom_minimum_size = Vector2(width - 20.0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var label_min := _tooltip_label.get_combined_minimum_size()
	if label_min.y <= 1.0:
		await get_tree().process_frame
		label_min = _tooltip_label.get_combined_minimum_size()
	var content_h: float = max(float(_tooltip_label.get_content_height()), label_min.y)
	var btn_h: float = 0.0
	if _tooltip_use_btn != null and _tooltip_use_btn.visible:
		btn_h = max(32.0, _tooltip_use_btn.get_combined_minimum_size().y)
	if _tooltip_equip_btn != null and _tooltip_equip_btn.visible:
		btn_h += max(32.0, _tooltip_equip_btn.get_combined_minimum_size().y)
	if _tooltip_sell_btn != null and _tooltip_sell_btn.visible:
		btn_h += max(32.0, _tooltip_sell_btn.get_combined_minimum_size().y)
	if _tooltip_quick_btn != null and _tooltip_quick_btn.visible:
		btn_h += max(32.0, _tooltip_quick_btn.get_combined_minimum_size().y)
	if _tooltip_bag_btn != null and _tooltip_bag_btn.visible:
		btn_h += max(32.0, _tooltip_bag_btn.get_combined_minimum_size().y)
	# label + optional button + small spacing
	var extra_spacing: float = 8.0 if btn_h > 0.0 else 0.0
	var min_h: float = max(32.0, content_h + btn_h + extra_spacing + 16.0)
	_tooltip_panel.custom_minimum_size = Vector2(width, min_h)
	_tooltip_panel.size = Vector2(width, min_h)
	# Finalize size after layout so first show doesn't resize on screen.
	await get_tree().process_frame
	await get_tree().process_frame
	var final_size := _tooltip_panel.get_combined_minimum_size()
	if final_size.y < min_h:
		final_size = Vector2(width, min_h)
	_tooltip_panel.custom_minimum_size = final_size
	_tooltip_panel.size = final_size
	_tooltip_panel.modulate = prev_modulate
	if not was_visible:
		_tooltip_panel.visible = false

func _position_tooltip_left_of_point(p: Vector2) -> void:
	if _tooltip_panel == null:
		return
	_position_panel_left_of_point(_tooltip_panel, p)

func _position_panel_left_of_point(target_panel: Control, p: Vector2) -> void:
	if target_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var size := target_panel.size
	var margin: float = 8.0
	var pos := Vector2(p.x - size.x - margin, p.y)
	if pos.x < margin:
		pos.x = margin
	if pos.y + size.y > vp.y - margin:
		pos.y = p.y - size.y
	pos.y = clamp(pos.y, margin, vp.y - size.y - margin)
	target_panel.position = pos

# --- Settings ---

func _is_settings_open() -> bool:
	return _settings_panel != null and _settings_panel.visible

func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible:
		_hide_tooltip()
		_sync_settings_columns_input(_grid_columns)
		_refresh_settings_columns_controls()

func _hide_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false

func _sync_settings_columns_input(cols: int) -> void:
	if _settings_value == null:
		return
	_settings_value.text = str(max(1, cols))

func _get_settings_columns_value() -> int:
	if _settings_value == null:
		return max(1, _grid_columns)
	var txt: String = _settings_value.text.strip_edges()
	if not txt.is_valid_int():
		return max(1, _grid_columns)
	return max(1, int(txt))

func _estimate_panel_width_for_columns(cols: int) -> float:
	var safe_cols: int = max(1, cols)
	var slot_w: float = 80.0
	if grid != null and grid.get_child_count() > 0:
		var first := grid.get_child(0) as Control
		if first != null:
			slot_w = max(1.0, first.get_combined_minimum_size().x)
	var hsep: float = float(grid.get_theme_constant("h_separation")) if grid != null else 0.0
	var grid_w: float = float(safe_cols) * slot_w + float(max(0, safe_cols - 1)) * hsep
	var pads: Dictionary = _compute_fixed_padding()
	var left_margin_x: float = float(pads.get("left_margin_x", 0.0))
	var pad_right: float = float(pads.get("pad_right", 10.0))
	var separation: float = float(pads.get("separation", 0.0))
	var bag_min: Vector2 = bag_slots.get_combined_minimum_size() if bag_slots != null else Vector2.ZERO
	return left_margin_x + bag_min.x + separation + grid_w + pad_right

func _get_max_fitting_columns(total_slots: int) -> int:
	if not _panel_anchor_valid:
		return max(1, min(20, total_slots))
	var cap: int = max(1, min(20, total_slots))
	var max_panel: Vector2 = _get_panel_max_size_from_anchor()
	var best: int = 1
	for c in range(1, cap + 1):
		if _estimate_panel_width_for_columns(c) <= max_panel.x:
			best = c
	return best

func _refresh_settings_columns_controls() -> void:
	if _settings_minus == null or _settings_plus == null:
		return
	var total: int = _get_total_inventory_slots()
	if total <= 0:
		total = _get_total_slots_from_player_fallback()
	if total <= 0:
		total = 1
	var max_fit: int = _get_max_fitting_columns(total)
	var current: int = clamp(_get_settings_columns_value(), 1, max_fit)
	_sync_settings_columns_input(current)
	_settings_minus.disabled = current <= 1
	_settings_plus.disabled = current >= max_fit

func _apply_columns_from_settings_value() -> void:
	var n: int = _get_settings_columns_value()
	if n <= 0:
		return
	var total: int = _get_total_inventory_slots()
	if total <= 0:
		total = _get_total_slots_from_player_fallback()
	if total <= 0:
		return

	var target_cols: int = clamp(max(1, n), 1, 20)
	var best_cols: int = target_cols
	var fits: bool = await _can_fit_columns(target_cols, total)
	if not fits:
		for c in range(target_cols, 0, -1):
			if await _can_fit_columns(c, total):
				best_cols = c
				break
		_sync_settings_columns_input(best_cols)
	if best_cols == _grid_columns:
		_refresh_settings_columns_controls()
		return
	_grid_columns = best_cols
	_save_grid_columns()
	_layout_dirty = true
	await _rebuild_layout("settings_change")
	_refresh_settings_columns_controls()
	await _refresh()

func _on_settings_minus_pressed() -> void:
	var current: int = _get_settings_columns_value()
	_sync_settings_columns_input(max(1, current - 1))
	await _apply_columns_from_settings_value()

func _on_settings_plus_pressed() -> void:
	var current: int = _get_settings_columns_value()
	_sync_settings_columns_input(current + 1)
	await _apply_columns_from_settings_value()



# --- Grid settings persistence + fit guard ---

func _load_grid_columns() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_GRID_CFG_PATH)
	if err == OK:
		var v: Variant = cfg.get_value(_GRID_CFG_SECTION, _GRID_CFG_KEY_COLUMNS, _grid_columns)
		if typeof(v) == TYPE_INT:
			_grid_columns = int(v)

func _save_grid_columns() -> void:
	var cfg := ConfigFile.new()
	# Preserve other values if file exists
	cfg.load(_GRID_CFG_PATH)
	cfg.set_value(_GRID_CFG_SECTION, _GRID_CFG_KEY_COLUMNS, _grid_columns)
	cfg.save(_GRID_CFG_PATH)

func _get_panel_max_size_from_anchor() -> Vector2:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if not _panel_anchor_valid:
		return vp_size
	var top_padding: float = 20.0
	var max_w: float = min(vp_size.x, _panel_br_anchor.x)
	var max_h: float = min(vp_size.y - top_padding, _panel_br_anchor.y - top_padding)
	max_h = max(0.0, max_h - 80.0)
	return Vector2(max_w, max_h)

func _compute_fixed_padding() -> Dictionary:
	var pad_right: float = 10.0
	var pad_bottom: float = 10.0
	var left_margin_x: float = 0.0
	var top_margin_y: float = 0.0
	var separation: float = 0.0
	if content != null:
		left_margin_x = content.offset_left
		top_margin_y = content.offset_top
		separation = float(content.get_theme_constant("separation"))
	return {
		"left_margin_x": left_margin_x,
		"top_margin_y": top_margin_y,
		"pad_right": pad_right,
		"pad_bottom": pad_bottom,
		"separation": separation
	}

func _compute_layout_for_columns(cols: int, total_slots: int) -> Dictionary:
	_ensure_grid_child_count(total_slots)
	grid.columns = max(1, cols)
	await get_tree().process_frame
	var grid_min: Vector2 = grid.get_combined_minimum_size()
	var max_panel: Vector2 = _get_panel_max_size_from_anchor()
	var pads: Dictionary = _compute_fixed_padding()
	var left_margin_x: float = float(pads.get("left_margin_x", 0.0))
	var top_margin_y: float = float(pads.get("top_margin_y", 0.0))
	var pad_right: float = float(pads.get("pad_right", 10.0))
	var pad_bottom: float = float(pads.get("pad_bottom", 10.0))
	var separation: float = float(pads.get("separation", 0.0))
	var bag_min: Vector2 = bag_slots.get_combined_minimum_size() if bag_slots != null else Vector2.ZERO
	var scroll_w: float = grid_min.x
	var scroll_h: float = grid_min.y
	var content_h: float = max(bag_min.y, scroll_h)
	var content_w: float = bag_min.x + separation + scroll_w
	var panel_w: float = left_margin_x + content_w + pad_right
	var panel_h: float = top_margin_y + content_h + pad_bottom
	var available_content_h: float = max(0.0, max_panel.y - top_margin_y - pad_bottom)
	var use_scroll: bool = grid_min.y > available_content_h + 0.5
	var scroll_view_h: float = min(grid_min.y, available_content_h)
	if not use_scroll:
		scroll_view_h = grid_min.y
	var scroll_view_size := Vector2(scroll_w, scroll_view_h)
	var panel_size := Vector2(panel_w, panel_h)
	return {
		"grid_min": grid_min,
		"scroll_view_size": scroll_view_size,
		"panel_size": panel_size,
		"use_scroll": use_scroll
	}

func _can_fit_columns(cols: int, total_slots: int) -> bool:
	if not _panel_anchor_valid:
		return true
	var max_panel: Vector2 = _get_panel_max_size_from_anchor()
	var layout: Dictionary = await _compute_layout_for_columns(cols, total_slots)
	var panel_size: Vector2 = layout.get("panel_size", Vector2.ZERO)
	return panel_size.x <= max_panel.x

func _apply_panel_br_anchor() -> void:
	if panel == null or not _panel_anchor_valid:
		return
	var max_panel: Vector2 = _get_panel_max_size_from_anchor()
	panel.size.x = min(panel.size.x, max_panel.x)
	panel.size.y = min(panel.size.y, max_panel.y)
	panel.position = _panel_br_anchor - panel.size

func _on_settings_sort() -> void:
	_sort_inventory_slots()
	await _refresh()

# --- Quick bar ---

func _on_quick_pressed(_index: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _index < 0 or _index >= _quick_refs.size():
		return
	var item_id: String = _quick_refs[_index]
	if item_id == "":
		return
	# Try to apply effect; only consume from inventory on success.
	var r: Dictionary = player.call("try_apply_consumable", item_id) as Dictionary
	if not bool(r.get("ok", false)):
		_show_consumable_fail_toast(String(r.get("reason", "")), item_id)
		return
	# Consume 1 item from inventory.
	var inv_comp: Node = player.get_node_or_null("Components/Inventory")
	if inv_comp != null and inv_comp.has_method("consume_item"):
		var removed: int = int(inv_comp.call("consume_item", item_id, 1))
		if removed <= 0:
			# no item actually removed; revert effect? for now just ignore.
			return
	# Refresh UI
	await _refresh()


func _is_quick_allowed_item(item_id: String) -> bool:
	# Quick slots are meant for usable items (food / potions / flasks, etc.).
	# At this stage we only need one strict rule: bags are NOT allowed.
	if item_id == "":
		return false
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item"):
		var meta: Dictionary = db.call("get_item", item_id) as Dictionary
		var typ: String = String(meta.get("type", ""))
		if typ.to_lower() == "bag":
			return false
	return true


func _is_consumable_item(item_id: String) -> bool:
	if item_id == "":
		return false
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return false
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	var typ: String = String(meta.get("type", "")).to_lower()
	return typ == "food" or typ == "drink" or typ == "potion"

func _is_equippable_item(item_id: String) -> bool:
	if item_id == "":
		return false
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return false
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	var typ: String = String(meta.get("type", "")).to_lower()
	return typ == "weapon" or typ == "armor" or typ == "accessory" or typ == "shield" or typ == "offhand"

func _get_default_equip_slot(item_id: String) -> String:
	if player != null and player.has_method("get_preferred_equipment_slot"):
		return String(player.call("get_preferred_equipment_slot", item_id))
	return ""


func _on_tooltip_use_pressed() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _tooltip_for_slot < 0 or _tooltip_for_bag_slot != -1:
		return
	# Grab current item in that slot (it could have changed).
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _tooltip_for_slot >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[_tooltip_for_slot]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	if not _is_consumable_item(id):
		return
	var r: Dictionary = player.call("try_apply_consumable", id) as Dictionary
	if not bool(r.get("ok", false)):
		_show_consumable_fail_toast(String(r.get("reason", "")), id)
		return
	var inv_comp: Node = player.get_node_or_null("Components/Inventory")
	if inv_comp != null and inv_comp.has_method("consume_item"):
		var removed: int = int(inv_comp.call("consume_item", id, 1))
		if removed <= 0:
			return
	_hide_tooltip()
	await _refresh()

func _on_tooltip_equip_pressed() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _tooltip_for_slot < 0 or _tooltip_for_bag_slot != -1:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _tooltip_for_slot >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[_tooltip_for_slot]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	if not _is_equippable_item(id):
		return
	var target_slot: String = _get_default_equip_slot(id)
	if target_slot == "":
		return
	if player.has_method("try_equip_from_inventory_slot"):
		var ok: bool = bool(player.call("try_equip_from_inventory_slot", _tooltip_for_slot, target_slot))
		if ok:
			_hide_tooltip()
			await _refresh()
		else:
			_show_equip_fail_toast()

func _on_tooltip_sell_pressed() -> void:
	if not _trade_open:
		return
	if player == null or not is_instance_valid(player):
		return
	if _tooltip_for_slot < 0 or _tooltip_for_bag_slot != -1:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _tooltip_for_slot >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[_tooltip_for_slot]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var d := v as Dictionary
	var id: String = String(d.get("id", ""))
	var count: int = int(d.get("count", 0))
	if id == "":
		return
	var total: int = _get_total_item_count(id)
	if total <= 0:
		return
	var merchant_ui := get_tree().get_first_node_in_group("merchant_ui")
	if merchant_ui == null:
		return
	if count <= 1 or _get_stack_max(id) <= 1:
		if merchant_ui.has_method("sell_items_from_inventory_slot"):
			merchant_ui.call("sell_items_from_inventory_slot", id, 1, _tooltip_for_slot)
		elif merchant_ui.has_method("sell_items_from_inventory"):
			merchant_ui.call("sell_items_from_inventory", id, 1)
		_hide_tooltip()
		await _refresh()
		return
	if merchant_ui.has_method("request_sell_from_inventory_slot"):
		merchant_ui.call("request_sell_from_inventory_slot", id, count, _tooltip_for_slot)
	elif merchant_ui.has_method("request_sell_from_inventory"):
		merchant_ui.call("request_sell_from_inventory", id, count)
	_hide_tooltip()
	await _refresh()

func _on_tooltip_quick_pressed() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _tooltip_for_slot < 0 or _tooltip_for_bag_slot != -1:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _tooltip_for_slot >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[_tooltip_for_slot]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	if not _is_consumable_item(id):
		return
	var existing := _get_quick_slot_index_for_item(id)
	if existing != -1:
		_quick_refs[existing] = ""
		_persist_quick_slots()
		_refresh_quick_bar()
		_hide_tooltip()
		return
	var empty := _get_first_empty_quick_slot()
	if empty == -1:
		show_center_toast(tr("ui.inventory.no_free_quick_slots"))
		return
	_quick_refs[empty] = id
	_persist_quick_slots()
	_refresh_quick_bar()
	_hide_tooltip()

func _on_tooltip_bag_pressed() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _tooltip_for_bag_slot != -1:
		var inv_slot := _find_first_free_slot(player.get_inventory_snapshot().get("slots", []))
		if inv_slot == -1:
			show_bag_full(tr("ui.common.bag_full"))
			return
		var ok: bool = player.try_unequip_bag_to_inventory(_tooltip_for_bag_slot, inv_slot)
		if ok:
			_hide_tooltip()
			await _refresh()
		else:
			show_bag_full(tr("ui.common.bag_full"))
		return
	if _tooltip_for_slot < 0:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if _tooltip_for_slot >= slots.size():
		_hide_tooltip()
		return
	var v: Variant = slots[_tooltip_for_slot]
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	if not _is_bag_item(id):
		return
	var bag_slots: Array = snap.get("bag_slots", [])
	var bag_index := _find_first_free_bag_slot(bag_slots)
	if bag_index == -1:
		show_center_toast(tr("ui.inventory.no_free_slots"))
		return
	var ok2: bool = player.try_equip_bag_from_inventory_slot(_tooltip_for_slot, bag_index)
	if ok2:
		_hide_tooltip()
		await _refresh()
	else:
		show_center_toast(tr("ui.inventory.no_free_slots"))


func _show_consumable_fail_toast(reason: String, item_id: String) -> void:
	_ensure_support_ui()
	if _toast_label == null:
		return
	var msg: String = ""
	match reason:
		"hp_full":
			msg = tr("ui.inventory.hp_full")
		"mp_full":
			msg = tr("ui.inventory.mp_full")
		"hpmp_full":
			msg = tr("ui.inventory.hpmp_full")
		_:
			# No message for cooldown/other cases for now.
			msg = ""
	if msg == "":
		return
	_toast_label.text = msg
	_toast_label.modulate = Color(1,1,1,1)
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast_label, "modulate", Color(1,1,1,0), 0.8)
	tw.finished.connect(func():
		if _toast_label != null:
			_toast_label.visible = false
	)

func _show_equip_fail_toast() -> void:
	_ensure_support_ui()
	if _toast_label == null:
		return
	if player == null or not is_instance_valid(player):
		return
	var reason := ""
	if player.has_method("get_last_equip_fail_reason"):
		reason = String(player.call("get_last_equip_fail_reason"))
	var msg := ""
	match reason:
		"level":
			msg = tr("ui.inventory.item_level_mismatch")
		"skill":
			msg = tr("ui.inventory.item_skill_mismatch")
		_:
			msg = ""
	if msg == "":
		return
	_toast_label.text = msg
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast_label, "modulate", Color(1, 1, 1, 0), 0.8)
	tw.finished.connect(func():
		if _toast_label != null:
			_toast_label.visible = false
	)

func show_center_toast(message: String) -> void:
	_ensure_support_ui()
	if _toast_label == null:
		return
	if message.strip_edges() == "":
		return
	_toast_label.text = message
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_label.visible = true
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast_label, "modulate", Color(1, 1, 1, 0), 0.8)
	tw.finished.connect(func():
		if _toast_label != null:
			_toast_label.visible = false
	)
func _show_tooltip_for_item_dict(d: Dictionary) -> void:
	_ensure_support_ui()
	var id: String = String(d.get("id", ""))
	var count: int = int(d.get("count", 0))
	# Same protection as slot tooltip: never show an empty/oversized background.
	_tooltip_panel.visible = false
	_tooltip_panel.custom_minimum_size = Vector2(_tooltip_panel.custom_minimum_size.x, 0)
	_tooltip_panel.size = Vector2(_tooltip_panel.size.x, 0)
	_tooltip_label.text = ""
	var text := _build_tooltip_text(id, count)
	if String(text).strip_edges() == "":
		await get_tree().process_frame
		text = _build_tooltip_text(id, count)
	_tooltip_label.text = text
	if _tooltip_use_btn != null:
		_tooltip_use_btn.visible = false
	if _tooltip_equip_btn != null:
		_tooltip_equip_btn.visible = false
	if _tooltip_sell_btn != null:
		_tooltip_sell_btn.visible = false
	if _tooltip_quick_btn != null:
		_tooltip_quick_btn.visible = false
	if _tooltip_bag_btn != null:
		_tooltip_bag_btn.visible = false
	await get_tree().process_frame
	if String(text).strip_edges() == "" or float(_tooltip_label.get_content_height()) <= 1.0:
		await get_tree().process_frame
		if String(text).strip_edges() == "" or float(_tooltip_label.get_content_height()) <= 1.0:
			return
	await _resize_tooltip_to_content()
	_tooltip_panel.visible = true
	_tooltip_for_slot = -999
	_tooltip_for_bag_slot = -1
	var mouse := get_viewport().get_mouse_position()
	_position_tooltip_left_of_point(mouse)

# --- Refresh & render ---

func _refresh() -> void:
	if _refresh_in_progress:
		_layout_dirty = true
		return
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("get_inventory_snapshot"):
		return
	_refresh_in_progress = true

	var snap: Dictionary = player.get_inventory_snapshot()
	_sync_quick_slots_from_snapshot(snap)
	var slots: Array = snap.get("slots", [])
	var bag_slots: Array = snap.get("bag_slots", [])
	var total_slots: int = slots.size()
	if total_slots == 0:
		total_slots = _get_total_slots_from_player_fallback()
	var bag_hash: int = str(bag_slots).hash()

	# Mark layout dirty only when geometry changes.
	if total_slots != _last_total_slots:
		_last_total_slots = total_slots
		_layout_dirty = true
	if bag_hash != _last_bag_slots_hash:
		_last_bag_slots_hash = bag_hash
		_layout_dirty = true
	if _grid_columns != _last_applied_columns:
		_layout_dirty = true
	var hide_cells: bool = _is_open and _layout_dirty
	if hide_cells:
		grid.modulate.a = 0.0

	# Ensure grid children exist, but don't reflow unless necessary.
	_ensure_grid_child_count(total_slots)
	_hook_slot_panels()

	if _layout_dirty:
		await _rebuild_layout("refresh_dirty")

	# Gold
	gold_label.text = _trf("ui.common.coins_with_value", {"value": TOOLTIP_BUILDER.format_money_bbcode(int(snap.get("gold", 0)))})

	# Render items
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null or not slot_panel.visible:
			continue
		_render_slot(slot_panel, i, slots)

	_update_bag_buttons(bag_slots)
	_refresh_quick_bar()
	if _is_open:
		grid.visible = true
		grid.modulate.a = 1.0
	_refresh_in_progress = false

func _refresh_quick_bar_snapshot() -> void:
	_ensure_support_ui()
	if not _is_player_ready():
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	_sync_quick_slots_from_snapshot(snap)
	_refresh_quick_bar()

func _render_slot(slot_panel: Panel, i: int, slots: Array) -> void:
	var icon: TextureRect = slot_panel.get_node_or_null("Icon") as TextureRect
	var count_label: Label = slot_panel.get_node_or_null("Count") as Label
	if i >= slots.size():
		if icon: icon.texture = null
		if count_label: count_label.text = ""
		_update_slot_cooldown(slot_panel, "")
		return
	var v: Variant = slots[i]
	if v == null or not (v is Dictionary):
		if icon: icon.texture = null
		if count_label: count_label.text = ""
		_update_slot_cooldown(slot_panel, "")
		return
	var d: Dictionary = v as Dictionary
	var id: String = String(d.get("id", ""))
	var count: int = int(d.get("count", 0))
	if id == "" or count <= 0:
		if icon: icon.texture = null
		if count_label: count_label.text = ""
		_update_slot_cooldown(slot_panel, "")
		return

	var db := get_node_or_null("/root/DataDB")
	var icon_path: String = ""
	if db != null and db.has_method("get_item"):
		var meta: Dictionary = db.call("get_item", id) as Dictionary
		icon_path = String(meta.get("icon", meta.get("icon_path", "")))
	var tex := _get_icon_texture(icon_path)
	if icon: icon.texture = tex
	if count_label:
		count_label.text = str(count) if count > 1 else ""
	_update_slot_cooldown(slot_panel, id)


func _get_consumable_cd_kind_for_item(item_id: String) -> String:
	if item_id == "":
		return ""
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return ""
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	var typ: String = String(meta.get("type", "")).to_lower()
	if typ == "potion":
		return "potion"
	if typ == "food" or typ == "drink":
		return "fooddrink"
	return ""


func _get_consumable_cd_total_for_kind(kind: String) -> float:
	# Design: potions 5s; food+drink 10s
	if kind == "potion":
		return 5.0
	if kind == "fooddrink":
		return 10.0
	return 0.0


func _update_slot_cooldown(slot_panel: Panel, item_id: String) -> void:
	var cd: ColorRect = slot_panel.get_node_or_null("Cooldown") as ColorRect
	if cd == null:
		return
	var kind: String = _get_consumable_cd_kind_for_item(item_id)
	if kind == "" or player == null:
		cd.visible = false
		return
	var left: float = 0.0
	if player.has_method("get_consumable_cooldown_left"):
		left = float(player.call("get_consumable_cooldown_left", kind))
	if left <= 0.01:
		cd.visible = false
		return
	cd.visible = true
	var lbl: Label = cd.get_node_or_null("CooldownText") as Label
	if lbl != null:
		lbl.text = str(int(ceil(left)))


func _update_quick_cooldown(btn: Button, item_id: String) -> void:
	if btn == null:
		return
	var cd: ColorRect = btn.get_node_or_null("Cooldown") as ColorRect
	if cd == null:
		return
	var kind: String = _get_consumable_cd_kind_for_item(item_id)
	if kind == "" or player == null:
		cd.visible = false
		return
	var left: float = 0.0
	if player.has_method("get_consumable_cooldown_left"):
		left = float(player.call("get_consumable_cooldown_left", kind))
	if left <= 0.01:
		cd.visible = false
		return
	cd.visible = true
	var lbl: Label = cd.get_node_or_null("CooldownText") as Label
	if lbl != null:
		lbl.text = str(int(ceil(left)))


func _update_visible_cooldowns(snap: Dictionary) -> void:
	# Update cooldown overlays without triggering any grid/panel relayout.
	var slots: Array = snap.get("slots", [])
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null or not slot_panel.visible:
			continue
		var item_id: String = ""
		if i < slots.size() and slots[i] is Dictionary:
			item_id = String((slots[i] as Dictionary).get("id", ""))
		_update_slot_cooldown(slot_panel, item_id)
	# Quick bar
	for qi in range(min(_quick_buttons.size(), _quick_refs.size())):
		var b := _quick_buttons[qi]
		_update_quick_cooldown(b, _quick_refs[qi])

func _update_bag_buttons(bag_slots: Array) -> void:
	# bag slots array is logical [0..3] (near base -> outward)
	for bi in range(4):
		var btn: Button = _get_bag_button_for_logical(bi)
		if btn == null:
			continue
		var v: Variant = bag_slots[bi] if bi < bag_slots.size() else null
		if v != null and v is Dictionary:
			var id: String = String((v as Dictionary).get("id", ""))
			var slots_count: int = 0
			var db := get_node_or_null("/root/DataDB")
			if db != null and db.has_method("get_item"):
				var item_d: Dictionary = db.call("get_item", id) as Dictionary
				if item_d.has("bag") and (item_d.get("bag") is Dictionary):
					slots_count = int((item_d.get("bag") as Dictionary).get("slots", 0))
			btn.text = "%d" % slots_count
			btn.disabled = false
		else:
			btn.text = ""
			btn.disabled = false

func show_bag_full(message: String = tr("ui.common.bag_full")) -> void:
	bag_full_dialog.dialog_text = message
	bag_full_dialog.popup_centered()

# --- Helpers ---

func _get_total_inventory_slots() -> int:
	if player == null:
		return 0
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	return slots.size()

func _find_first_free_slot(slots: Array) -> int:
	for i in range(slots.size()):
		if slots[i] == null:
			return i
	return -1

func _find_first_free_bag_slot(bag_slots: Array) -> int:
	for i in range(min(4, bag_slots.size())):
		if bag_slots[i] == null:
			return i
	return -1

func _get_quick_slot_index_for_item(item_id: String) -> int:
	for i in range(_quick_refs.size()):
		if _quick_refs[i] == item_id:
			return i
	return -1

func _get_first_empty_quick_slot() -> int:
	for i in range(_quick_refs.size()):
		if _quick_refs[i] == "":
			return i
	return -1

func _get_total_item_count(item_id: String) -> int:
	if item_id == "":
		return 0
	if player == null:
		return 0
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var total: int = 0
	for v in slots:
		if v == null or not (v is Dictionary):
			continue
		var d: Dictionary = v as Dictionary
		if String(d.get("id", "")) == item_id:
			total += int(d.get("count", 0))
	return total

func is_point_over_inventory(global_pos: Vector2) -> bool:
	if panel == null or not panel.visible:
		return false
	return panel.get_global_rect().has_point(global_pos)

func _find_first_slot_with_item(id: String) -> int:
	if player == null:
		return -1
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	for i in range(slots.size()):
		var v: Variant = slots[i]
		if v is Dictionary and String((v as Dictionary).get("id", "")) == id:
			return i
	return -1

func _is_bag_item(id: String) -> bool:
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item"):
		var d: Dictionary = db.call("get_item", id) as Dictionary
		return String(d.get("type", "")) == "bag"
	return false

func _get_stack_max(id: String) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var db := tree.root.get_node_or_null("/root/DataDB")
		if db != null and db.has_method("get_item_stack_max"):
			return max(1, int(db.call("get_item_stack_max", id)))
	return 1

func _get_icon_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[path] = tex
	return tex

func _is_point_inside_panel(global_pos: Vector2) -> bool:
	var rect := panel.get_global_rect()
	return rect.has_point(global_pos)

func _get_slot_index_under_global(global_pos: Vector2) -> int:
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null or not slot_panel.visible:
			continue
		if slot_panel.get_global_rect().has_point(global_pos):
			return i
	return -1

func _build_tooltip_text(id: String, count: int) -> String:
	var db := get_node_or_null("/root/DataDB")
	var meta: Dictionary = {}
	if db != null and db.has_method("get_item"):
		meta = db.call("get_item", id) as Dictionary
	return TOOLTIP_BUILDER.build_item_tooltip(meta, count, player)






func rarity_idx(r: String) -> int:
	var rr := r.to_lower()
	match rr:
		"common":
			return 0
		"uncommon":
			return 1
		"rare":
			return 2
		"epic":
			return 3
		"legendary":
			return 4
		_:
			return 0

func _sort_inventory_slots() -> void:
	if player == null:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	# Keep nulls, sort only items
	var items: Array[Dictionary] = []
	for v in slots:
		if v is Dictionary:
			items.append((v as Dictionary).duplicate(true))
	# Sort key (nested): type -> required level -> rarity -> subtype/material -> name
	# NOTE: per your request, string keys are sorted alphabetically.
	var db := get_node_or_null("/root/DataDB")
	var subtype_key := func(meta: Dictionary, fallback_id: String) -> String:
		var t: String = String(meta.get("type", ""))
		if t == "armor" and meta.get("armor") is Dictionary:
			var a: Dictionary = meta.get("armor") as Dictionary
			# material/class first, then slot to keep similar armor grouped
			return "%s_%s" % [String(a.get("class", "")), String(a.get("slot", ""))]
		if t == "weapon" and meta.get("weapon") is Dictionary:
			var w: Dictionary = meta.get("weapon") as Dictionary
			# subtype + handed (1h/2h) keeps weapons grouped logically
			return "%s_%s" % [String(w.get("subtype", "")), String(w.get("handed", ""))]
		# Fallback: use id (stable, alphabetical)
		return fallback_id

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ida := String(a.get("id",""))
		var idb := String(b.get("id",""))
		var ma: Dictionary = db.call("get_item", ida) as Dictionary if db != null and db.has_method("get_item") else {}
		var mb: Dictionary = db.call("get_item", idb) as Dictionary if db != null and db.has_method("get_item") else {}
		var ta := String(ma.get("type",""))
		var tb := String(mb.get("type",""))
		if ta != tb:
			return ta < tb
		var la: int = int(ma.get("required_level", ma.get("item_level", 0)))
		var lb: int = int(mb.get("required_level", mb.get("item_level", 0)))
		if la != lb:
			return la < lb
		var rna: String = String(ma.get("rarity", ""))
		var rnb: String = String(mb.get("rarity", ""))
		if rna != rnb:
			return rna < rnb
		var sa: String = subtype_key.call(ma, ida)
		var sb: String = subtype_key.call(mb, idb)
		if sa != sb:
			return sa < sb
		var na := String(ma.get("name", ida))
		var nb := String(mb.get("name", idb))
		return na < nb
	)

	# Merge stacks after sorting.
	var stacked: Array[Dictionary] = []
	for item in items:
		var id := String(item.get("id", ""))
		var remaining := int(item.get("count", 0))
		var max_stack := _get_stack_max(id)
		while remaining > 0:
			if stacked.size() > 0 and String(stacked[-1].get("id", "")) == id:
				var last_count := int(stacked[-1].get("count", 0))
				if last_count < max_stack:
					var can_add: int = min(remaining, max_stack - last_count)
					stacked[-1]["count"] = last_count + can_add
					remaining -= can_add
					continue
			var take: int = min(remaining, max_stack)
			stacked.append({"id": id, "count": take})
			remaining -= take

	# Refill slots sequentially, keep same total size
	for i in range(slots.size()):
		slots[i] = null
	for i in range(min(slots.size(), stacked.size())):
		slots[i] = stacked[i]
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)

func _ensure_support_ui() -> void:
	# Tooltip nodes are part of InventoryHUD.tscn (same approach as LootHUD).
	if _tooltip_panel == null:
		_tooltip_panel = tooltip_panel_scene
		_tooltip_label = tooltip_label_scene
		_tooltip_use_btn = tooltip_use_btn_scene
		_tooltip_equip_btn = tooltip_equip_btn_scene
		_tooltip_sell_btn = tooltip_sell_btn_scene
		_tooltip_quick_btn = tooltip_quick_btn_scene
		_tooltip_bag_btn = tooltip_bag_btn_scene
		_tooltip_close_btn = tooltip_close_btn_scene
		if _tooltip_panel != null:
			_tooltip_panel.visible = false
			_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_PASS
			_ensure_tooltip_layer()
			_ensure_dialog_layer()
			_ensure_error_layer()
			# Match LootHUD tooltip styling.
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0.85)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(1, 1, 1, 0.12)
			sb.corner_radius_top_left = 8
			sb.corner_radius_top_right = 8
			sb.corner_radius_bottom_left = 8
			sb.corner_radius_bottom_right = 8
			_tooltip_panel.add_theme_stylebox_override("panel", sb)
			_tooltip_panel.custom_minimum_size = Vector2(360, 0)
		if _tooltip_label != null:
			_tooltip_label.bbcode_enabled = true
			_tooltip_label.fit_content = true
			_tooltip_label.scroll_active = false
			_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _tooltip_use_btn != null and not _tooltip_use_btn.pressed.is_connected(_on_tooltip_use_pressed):
			_tooltip_use_btn.pressed.connect(_on_tooltip_use_pressed)
		if _tooltip_equip_btn != null and not _tooltip_equip_btn.pressed.is_connected(_on_tooltip_equip_pressed):
			_tooltip_equip_btn.pressed.connect(_on_tooltip_equip_pressed)
		if _tooltip_sell_btn != null and not _tooltip_sell_btn.pressed.is_connected(_on_tooltip_sell_pressed):
			_tooltip_sell_btn.pressed.connect(_on_tooltip_sell_pressed)
		if _tooltip_quick_btn != null and not _tooltip_quick_btn.pressed.is_connected(_on_tooltip_quick_pressed):
			_tooltip_quick_btn.pressed.connect(_on_tooltip_quick_pressed)
		if _tooltip_bag_btn != null and not _tooltip_bag_btn.pressed.is_connected(_on_tooltip_bag_pressed):
			_tooltip_bag_btn.pressed.connect(_on_tooltip_bag_pressed)
		if _tooltip_close_btn != null and not _tooltip_close_btn.pressed.is_connected(_hide_tooltip):
			_tooltip_close_btn.pressed.connect(_hide_tooltip)

	if split_dialog != null:
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0,0,0,0.8)
		sb2.content_margin_left = 10
		sb2.content_margin_right = 10
		sb2.content_margin_top = 10
		sb2.content_margin_bottom = 10
		split_dialog.add_theme_stylebox_override("panel", sb2)
		if split_slider != null and not split_slider.value_changed.is_connected(_on_split_value_changed):
			split_slider.value_changed.connect(_on_split_value_changed)
		if split_ok != null and not split_ok.pressed.is_connected(_on_split_ok_pressed):
			split_ok.pressed.connect(_on_split_ok_pressed)
		if split_cancel != null and not split_cancel.pressed.is_connected(_on_split_cancel_pressed):
			split_cancel.pressed.connect(_on_split_cancel_pressed)
		_ensure_dialog_layer()
		if split_dialog.get_parent() != _dialog_layer:
			split_dialog.reparent(_dialog_layer)

	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.name = "CenterToast"
		_toast_label.visible = false
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ensure_error_layer()
		_error_layer.add_child(_toast_label)
		# Center in viewport
		_toast_label.set_anchors_preset(Control.PRESET_CENTER)
		_toast_label.offset_left = -180
		_toast_label.offset_top = -20
		_toast_label.offset_right = 180
		_toast_label.offset_bottom = 20
		_toast_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(0, 0, 0, 0.75)
		tsb.corner_radius_top_left = 8
		tsb.corner_radius_top_right = 8
		tsb.corner_radius_bottom_left = 8
		tsb.corner_radius_bottom_right = 8
		tsb.content_margin_left = 12
		tsb.content_margin_right = 12
		tsb.content_margin_top = 6
		tsb.content_margin_bottom = 6
		_toast_label.add_theme_stylebox_override("normal", tsb)

	if bag_full_dialog != null:
		_ensure_error_layer()
		if bag_full_dialog.get_parent() != _error_layer:
			bag_full_dialog.reparent(_error_layer)

	if _settings_button == null:
		_settings_button = settings_button_scene
	if _settings_button != null:
		_settings_button.text = "⋮"
		if not _settings_button.pressed.is_connected(_toggle_settings):
			_settings_button.pressed.connect(_toggle_settings)

	if _settings_panel == null:
		_settings_panel = settings_panel_scene
	if _settings_button != null and _settings_button.get_parent() == panel:
		panel.move_child(_settings_button, panel.get_child_count() - 1)

	if _settings_panel != null and _settings_panel.get_parent() == panel:
		panel.move_child(_settings_panel, panel.get_child_count() - 1)

	if _settings_panel != null:
		_settings_title_label = settings_title_label_scene
		_settings_columns_label = settings_columns_label_scene
		_settings_minus = settings_minus_scene
		_settings_value = settings_value_scene
		_settings_plus = settings_plus_scene
		_settings_sort_title = settings_sort_title_scene
		_settings_sort = settings_sort_scene
		_settings_panel.visible = false
		if _settings_title_label != null:
			_settings_title_label.text = tr("ui.inventory.settings.title")
		if _settings_columns_label != null:
			_settings_columns_label.text = tr("ui.inventory.settings.columns")
		if _settings_minus != null:
			_settings_minus.text = "-"
			if not _settings_minus.pressed.is_connected(_on_settings_minus_pressed):
				_settings_minus.pressed.connect(_on_settings_minus_pressed)
		if _settings_plus != null:
			_settings_plus.text = "+"
			if not _settings_plus.pressed.is_connected(_on_settings_plus_pressed):
				_settings_plus.pressed.connect(_on_settings_plus_pressed)
		if _settings_sort_title != null:
			_settings_sort_title.text = tr("ui.inventory.settings.sort_title")
		if _settings_sort != null:
			_settings_sort.text = tr("ui.inventory.settings.sort")
			if not _settings_sort.pressed.is_connected(_on_settings_sort):
				_settings_sort.pressed.connect(_on_settings_sort)
		_sync_settings_columns_input(_grid_columns)
		_refresh_settings_columns_controls()

	# Quick bar is part of the scene (InventoryHUD.tscn) so you can edit it visually.
	if _quick_bar == null:
		_quick_bar = get_node_or_null("Root/QuickBar") as HBoxContainer
		if _quick_bar == null:
			push_error("InventoryHUD: QuickBar node missing from scene; quick slots disabled.")
			return
		# Collect 5 buttons from the scene (no runtime-created quick bar).
		_quick_buttons = []
		var kids := _quick_bar.get_children()
		for i in range(min(5, kids.size())):
			var b := kids[i] as Button
			if b != null:
				_quick_buttons.append(b)
		if _quick_buttons.size() < 5:
			push_error("InventoryHUD: QuickBar needs 5 buttons in the scene.")
			return
		for i in range(5):
			var b := _quick_buttons[i]
			b.text = ""
			b.icon = null
			_ensure_quick_button_visuals(b)
			var icon := _get_quick_icon(b)
			var count_label := _get_quick_count_label(b)
			if icon == null or count_label == null:
				push_error("InventoryHUD: QuickBar button %d missing Icon/Count nodes." % i)
				return
			icon.texture = null
			count_label.text = ""
			var cb := Callable(self, "_on_quick_pressed").bind(i)
			if not b.pressed.is_connected(cb):
				b.pressed.connect(cb)
		_refresh_quick_bar()


func _style_inventory_tooltip() -> void:
	# Match LootHUD tooltip background and padding.
	if _tooltip_panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	_tooltip_panel.add_theme_stylebox_override("panel", sb)
	# Make sure RichTextLabel behaves consistently.
	if _tooltip_label != null:
		_tooltip_label.bbcode_enabled = true
		_tooltip_label.fit_content = true
		_tooltip_label.scroll_active = false
		_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD


func _ensure_quick_button_visuals(b: Button) -> void:
	# Cooldown overlay for quick slots.
	var cd := b.get_node_or_null("Cooldown") as ColorRect
	if cd == null:
		cd = ColorRect.new()
		cd.name = "Cooldown"
		cd.color = Color(0, 0, 0, 0.65)
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cd)
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.offset_left = 0
		cd.offset_top = 0
		cd.offset_right = 0
		cd.offset_bottom = 0
		var cd_lbl := Label.new()
		cd_lbl.name = "CooldownText"
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.add_child(cd_lbl)
		cd_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd_lbl.offset_left = 0
		cd_lbl.offset_top = 0
		cd_lbl.offset_right = 0
		cd_lbl.offset_bottom = 0

func _get_quick_icon(btn: Button) -> TextureRect:
	if btn == null:
		return null
	return btn.get_node_or_null("Icon") as TextureRect

func _get_quick_count_label(btn: Button) -> Label:
	if btn == null:
		return null
	return btn.get_node_or_null("Count") as Label

func _sync_quick_slots_from_snapshot(snap: Dictionary) -> void:
	if _quick_slots_syncing:
		return
	if not snap.has("quick_slots"):
		return
	var quick_v: Variant = snap.get("quick_slots", [])
	if not (quick_v is Array):
		return
	var quick_arr: Array = quick_v as Array
	var next: Array[String] = []
	next.resize(5)
	for i in range(5):
		next[i] = String(quick_arr[i]) if i < quick_arr.size() else ""
	if next != _quick_refs:
		_quick_refs = next

func _persist_quick_slots() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _quick_slots_syncing:
		return
	_quick_slots_syncing = true
	if player.has_method("set_quick_slots"):
		player.call("set_quick_slots", _quick_refs.duplicate())
	elif player.has_method("get_inventory_snapshot") and player.has_method("apply_inventory_snapshot"):
		var snap: Dictionary = player.get_inventory_snapshot()
		snap["quick_slots"] = _quick_refs.duplicate()
		player.apply_inventory_snapshot(snap)
	_quick_slots_syncing = false

func _refresh_quick_bar() -> void:
	if _quick_buttons.size() != 5:
		return
	if player == null:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var db := get_node_or_null("/root/DataDB")
	var quick_changed: bool = false
	for i in range(5):
		var b := _quick_buttons[i]
		var icon := _get_quick_icon(b)
		var count_label := _get_quick_count_label(b)
		if icon == null or count_label == null:
			continue
		var item_id: String = _quick_refs[i]
		if item_id == "":
			icon.texture = null
			count_label.text = ""
			_update_quick_cooldown(b, "")
			continue
		# Sum counts across all stacks in inventory
		var total: int = 0
		for v in slots:
			if v is Dictionary and String((v as Dictionary).get("id","")) == item_id:
				total += int((v as Dictionary).get("count", 0))
		if total <= 0:
			# Item no longer present; clear quick slot
			if _quick_refs[i] != "":
				_quick_refs[i] = ""
				quick_changed = true
			icon.texture = null
			count_label.text = ""
			continue
		var meta: Dictionary = db.call("get_item", item_id) as Dictionary if db != null and db.has_method("get_item") else {}
		var icon_path: String = String(meta.get("icon", meta.get("icon_path","")))
		icon.texture = _get_icon_texture(icon_path)
		count_label.text = str(total) if total > 1 else ""
		_update_quick_cooldown(b, item_id)
	if quick_changed:
		_persist_quick_slots()

func _rebuild_layout(reason: String) -> void:
	if _rebuild_in_progress:
		_rebuild_requested = true
		return
	_rebuild_in_progress = true
	if not _is_player_ready():
		_rebuild_in_progress = false
		return
	var total_slots: int = _get_total_inventory_slots()
	if total_slots <= 0:
		total_slots = _get_total_slots_from_player_fallback()
	await _apply_layout_sizes(total_slots)
	if _is_open:
		grid.modulate.a = 1.0
	_rebuild_in_progress = false
	if _rebuild_requested:
		_rebuild_requested = false
		call_deferred("_rebuild_layout", "queued")

func _apply_layout_sizes(total_slots: int) -> Dictionary:
	if panel == null or grid == null or grid_scroll == null or content == null:
		return {}
	_ensure_grid_child_count(total_slots)
	grid.columns = max(1, _grid_columns)
	grid.custom_minimum_size = Vector2.ZERO
	grid_scroll.custom_minimum_size = Vector2.ZERO
	if grid_scroll_wrapper != null:
		grid_scroll_wrapper.custom_minimum_size = Vector2.ZERO
	grid.size = Vector2.ZERO
	await get_tree().process_frame
	var grid_min: Vector2 = grid.get_combined_minimum_size()
	var bag_min: Vector2 = bag_slots.get_combined_minimum_size() if bag_slots != null else Vector2.ZERO
	var separation: float = float(content.get_theme_constant("separation")) if content != null else 0.0
	var left_offset: float = content.offset_left if content != null else 0.0
	var top_offset: float = content.offset_top if content != null else 0.0
	var pad_right: float = 10.0
	var pad_bottom: float = 10.0
	var max_panel: Vector2 = _get_panel_max_size_from_anchor()
	var available_content_h: float = max(0.0, max_panel.y - top_offset - pad_bottom)
	var use_scroll: bool = grid_min.y > available_content_h + 0.5
	var scroll_view_h: float = min(grid_min.y, available_content_h)
	if not use_scroll:
		scroll_view_h = grid_min.y

	if grid_scroll_wrapper != null:
		grid_scroll_wrapper.custom_minimum_size = Vector2(grid_min.x, scroll_view_h)
	grid_scroll.custom_minimum_size = Vector2(grid_min.x, scroll_view_h)
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if use_scroll else ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid_scroll.size_flags_stretch_ratio = 0.0
	if content != null:
		content.queue_sort()
	await get_tree().process_frame

	var panel_w: float = left_offset + bag_min.x + separation + grid_min.x + pad_right
	var panel_h: float = top_offset + max(bag_min.y, scroll_view_h) + pad_bottom
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.size = panel.custom_minimum_size
	_apply_panel_br_anchor()
	_last_applied_columns = _grid_columns
	_layout_dirty = false

	# Keep settings button pinned to top-right and panel attached to button.
	if _settings_button != null:
		_settings_button.position = Vector2(panel.size.x - _settings_button.size.x - 8.0, 8.0)
	if _settings_panel != null and _settings_button != null:
		var anchor_point := _settings_button.position + Vector2(0.0, _settings_button.size.y) + Vector2(-8.0, 8.0)
		_settings_panel.position = Vector2(anchor_point.x - _settings_panel.size.x, anchor_point.y)
	return {
		"panel_size": panel.size,
		"scroll_view": Vector2(grid_min.x, scroll_view_h)
	}


func _ensure_tooltip_layer() -> void:
	if _tooltip_panel == null:
		return
	if _tooltip_layer == null:
		_tooltip_layer = CanvasLayer.new()
		_tooltip_layer.name = "TooltipLayer"
		_tooltip_layer.layer = 200
		add_child(_tooltip_layer)
	if _tooltip_panel.get_parent() != _tooltip_layer:
		_tooltip_panel.reparent(_tooltip_layer)

func _ensure_dialog_layer() -> void:
	if _dialog_layer == null:
		_dialog_layer = CanvasLayer.new()
		_dialog_layer.name = "DialogLayer"
		_dialog_layer.layer = 210
		add_child(_dialog_layer)

func _ensure_error_layer() -> void:
	if _error_layer == null:
		_error_layer = CanvasLayer.new()
		_error_layer.name = "ErrorLayer"
		_error_layer.layer = 220
		add_child(_error_layer)

func _force_initial_layout() -> void:
	if _initial_layout_done:
		return
	if _initial_layout_pending:
		return
	_initial_layout_pending = true
	await _run_initial_layout()

func _run_initial_layout() -> void:
	if player == null or not is_instance_valid(player):
		_initial_layout_pending = false
		return
	if not player.has_method("get_inventory_snapshot"):
		_initial_layout_pending = false
		return
	_load_grid_columns()
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if slots.size() <= 0:
		_initial_layout_pending = false
		return
	_layout_dirty = true
	await _rebuild_layout("initial")
	_initial_layout_done = true
	_initial_layout_pending = false
