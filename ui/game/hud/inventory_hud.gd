extends CanvasLayer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")
@onready var panel: Control = $Panel
@onready var gold_label: Label = $Panel/GoldLabel
@onready var grid: GridContainer = $Panel/Grid

@onready var base_bag_button: Button = $BagBar/BaseBagButton
@onready var bag_slot1: Button = $BagBar/BagSlot1
@onready var bag_slot2: Button = $BagBar/BagSlot2
@onready var bag_slot3: Button = $BagBar/BagSlot3
@onready var bag_slot4: Button = $BagBar/BagSlot4

@onready var bag_full_dialog: AcceptDialog = $BagFullDialog

# Tooltip is defined in the scene (like LootHUD), not created dynamically.
@onready var tooltip_panel_scene: Panel = $InvTooltip
@onready var tooltip_label_scene: RichTextLabel = $InvTooltip/Margin/VBox/Text
@onready var tooltip_use_btn_scene: Button = $InvTooltip/Margin/VBox/UseButton
@onready var tooltip_equip_btn_scene: Button = $InvTooltip/Margin/VBox/EquipButton
@onready var tooltip_sell_btn_scene: Button = $InvTooltip/Margin/VBox/SellButton

var player: Node = null
var _is_open: bool = true
var _trade_open: bool = false

# --- Inventory UI state ---
var _selected_slot_index: int = -1

# Drag state (picked item that follows cursor)
var _drag_active: bool = false
var _drag_from_slot: int = -1
var _drag_from_bag_index: int = -1  # when dragging from bag equipment slot
var _drag_from_bag: bool = false
var _drag_item: Dictionary = {} # {"id": String, "count": int}
var _drag_started: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_threshold: float = 10.0

# Used to restore on cancel/delete "No"
var _drag_restore_snapshot: Dictionary = {}

# Click timing for double-click split
var _last_click_time_ms: int = 0
var _last_click_slot: int = -1
var _double_click_ms: int = 320

# Tooltip (fixed width, grows in height; supports rich color for required level)
var _tooltip_panel: Panel = null
var _tooltip_label: RichTextLabel = null
var _tooltip_use_btn: Button = null
var _tooltip_equip_btn: Button = null
var _tooltip_sell_btn: Button = null
var _tooltip_for_slot: int = -1

# Small center toast ("hp full" / "mana full")
var _toast_label: Label = null

# Delete confirm dialog shown when drop outside panel
var _delete_confirm: ConfirmationDialog = null

# Split dialog
var _split_dialog: Panel = null
var _split_slider: HSlider = null
var _split_label: Label = null
var _split_ok: Button = null
var _split_cancel: Button = null
var _split_source_slot: int = -1

# Settings UI (columns/rows + sort)
var _settings_button: Button = null
var _settings_panel: Panel = null
var _settings_mode: OptionButton = null
var _settings_input: LineEdit = null
var _settings_apply: Button = null
var _settings_sort: Button = null

var _grid_columns: int = 4 # default layout for 16 slots

const _GRID_CFG_PATH := "user://inventory_grid.cfg"
const _GRID_CFG_SECTION := "inventory_hud"
const _GRID_CFG_KEY_COLUMNS := "grid_columns"

# Quick slots (5) - references to inventory slot indices
var _quick_bar: VBoxContainer = null
var _quick_buttons: Array[Button] = []
var _quick_refs: Array[String] = ["", "", "", "", ""]  # item_id per quick slot

# Dragging out of quick slots only removes the quick reference (item stays in inventory).
var _quick_drag_active: bool = false
var _quick_drag_index: int = -1
var _quick_drag_item: Dictionary = {}

# Lightweight refresh while inventory is open (so looting updates immediately).
var _refresh_accum: float = 0.0

# Layout recalculation should only happen when grid geometry changes (startup,
# apply settings, or bag slots changing total slot count). Regular item moves
# should not trigger any resizing/re-anchoring.
var _layout_dirty: bool = true
var _layout_recalc_in_progress: bool = false
var _last_total_slots: int = -1
var _last_applied_columns: int = -1
var _last_snap_hash: int = 0

# Layout anchor: keep panel growing towards screen center (up + left) from a stable bottom-right point
var _panel_anchor_br: Vector2 = Vector2.ZERO
var _panel_anchor_valid: bool = false

# Icon cache for slot buttons
var _icon_cache: Dictionary = {} # path -> Texture2D

func _ready() -> void:
	add_to_group("inventory_ui")
	# default to closed in actual gameplay; keep current behavior
	_is_open = panel.visible

	base_bag_button.pressed.connect(_on_bag_button_pressed)
	# Bag equipment slots (visual order: they extend left from base bag button).
	# Logical bag order must start near base bag and go left.
	_get_bag_button_for_logical(0).pressed.connect(_on_bag_slot_pressed.bind(0))
	_get_bag_button_for_logical(1).pressed.connect(_on_bag_slot_pressed.bind(1))
	_get_bag_button_for_logical(2).pressed.connect(_on_bag_slot_pressed.bind(2))
	_get_bag_button_for_logical(3).pressed.connect(_on_bag_slot_pressed.bind(3))

	# Enable dragging bags out of equipment slots (only if empty).
	_get_bag_button_for_logical(0).gui_input.connect(_on_bag_button_gui_input.bind(0))
	_get_bag_button_for_logical(1).gui_input.connect(_on_bag_button_gui_input.bind(1))
	_get_bag_button_for_logical(2).gui_input.connect(_on_bag_button_gui_input.bind(2))
	_get_bag_button_for_logical(3).gui_input.connect(_on_bag_button_gui_input.bind(3))

	_ensure_support_ui()
	_style_inventory_tooltip()
	_hook_slot_panels()
	_auto_bind_player()
	_load_grid_columns()
	# Capture the bottom-right anchor based on where you placed the panel in the scene.
	# This anchor will be used for all future resizes so the panel grows up+left.
	await get_tree().process_frame
	var rect := panel.get_global_rect()
	_panel_anchor_br = rect.position + rect.size
	_panel_anchor_valid = true
	_refresh()

func set_player(p: Node) -> void:
	player = p
	_refresh()

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
		return
	# Fallback by common node name.
	var root := get_tree().current_scene
	if root == null:
		return
	var p := root.find_child("Player", true, false)
	if p != null:
		player = p

func _process(_delta: float) -> void:
	if _drag_active or _quick_drag_active:
		_update_drag_visual()

	# While open, keep HUD in sync (so looting updates without requiring sort).
	if _is_open and player != null and is_instance_valid(player) and player.has_method("get_inventory_snapshot"):
		_refresh_accum += _delta
		if _refresh_accum >= 0.12:
			_refresh_accum = 0.0
			var snap: Dictionary = player.get_inventory_snapshot()
			var h: int = str(snap).hash()
			if h != _last_snap_hash:
				_last_snap_hash = h
				_refresh()
			# Cooldowns tick even if inventory content didn't change.
			_update_visible_cooldowns(snap)

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var e := event as InputEventMouseButton
		var m := get_viewport().get_mouse_position()
		if e.pressed:
			# Start quick-drag if pressed on a quick slot and we're not already dragging an inventory item.
			if not _drag_active and not _quick_drag_active:
				var q := _get_quick_index_under_global(m)
				if q != -1 and _quick_refs[q] != "":
					_start_quick_drag(q)
		else:
			# Release quick drag: drop onto another quick slot -> swap; otherwise remove link.
			if _quick_drag_active:
				var q2 := _get_quick_index_under_global(m)
				if q2 != -1:
					var tmp := _quick_refs[q2]
					_quick_refs[q2] = _quick_refs[_quick_drag_index]
					_quick_refs[_quick_drag_index] = tmp
				else:
					_quick_refs[_quick_drag_index] = ""
				_quick_drag_active = false
				_quick_drag_index = -1
				_quick_drag_item = {}
				_hide_drag_visual()
				_refresh_quick_bar()

func _toggle_inventory() -> void:
	_set_open(not _is_open)

func _set_open(v: bool) -> void:
	_is_open = v
	panel.visible = v
	if not v:
		_hide_tooltip()
		_cancel_drag_restore()
		_hide_split()
		_hide_settings()

func _on_bag_button_pressed() -> void:
	_toggle_inventory()

# --- Bag slots ---

func _get_bag_button_for_logical(logical_index: int) -> Button:
	# UI order (left->right): BagSlot1 BagSlot2 BagSlot3 BagSlot4 BaseBagButton
	# We want logical order from BaseBag outward to the left:
	# logical 0 -> BagSlot4, 1 -> BagSlot3, 2 -> BagSlot2, 3 -> BagSlot1
	match logical_index:
		0: return bag_slot4
		1: return bag_slot3
		2: return bag_slot2
		3: return bag_slot1
		_: return bag_slot4

func _on_bag_slot_pressed(_bag_index: int) -> void:
	# Any bag click toggles inventory open/close.
	# Bag equip/unequip is done via drag&drop.
	_toggle_inventory()


# --- Bag slot drag (unequip) ---

var _bag_drag_start_pos: Vector2 = Vector2.ZERO
var _bag_drag_threshold: float = 10.0
var _bag_drag_pending_index: int = -1

func _on_bag_button_gui_input(event: InputEvent, bag_index: int) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_bag_drag_pending_index = bag_index
				_bag_drag_start_pos = mb.position
			else:
				if _drag_active and _drag_from_bag and _drag_from_bag_index == bag_index:
					_finish_drag(mb.global_position)
				_bag_drag_pending_index = -1
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _bag_drag_pending_index == bag_index:
			if not _drag_active:
				var dist := _bag_drag_start_pos.distance_to(mm.position)
				if dist >= _bag_drag_threshold:
					_start_drag_from_bag_slot(bag_index, mm.global_position)

func _start_drag_from_bag_slot(bag_index: int, _global_pos: Vector2) -> void:
	if _drag_active:
		return
	if player == null or not is_instance_valid(player):
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var bags: Array = snap.get("bag_slots", [])
	if bag_index < 0 or bag_index >= bags.size():
		return
	var v: Variant = bags[bag_index]
	if v == null or not (v is Dictionary):
		return
	_drag_item = (v as Dictionary).duplicate(true)
	_drag_from_bag = true
	_drag_from_bag_index = bag_index
	_drag_from_slot = -1
	_drag_active = true
	_show_drag_visual()
	_hide_tooltip()

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
	if not _is_open:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_started = false
				_drag_start_pos = mb.position
				_on_slot_press(slot_index)
			else:
				_on_slot_release(slot_index, mb.global_position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _drag_active:
				var dist := _drag_start_pos.distance_to(mm.position)
				if dist >= _drag_threshold:
					_start_drag_from_slot(slot_index, mm.global_position)

func _on_slot_press(slot_index: int) -> void:
	# Double click detection for split
	var now_ms: int = Time.get_ticks_msec()
	if _last_click_slot == slot_index and (now_ms - _last_click_time_ms) <= _double_click_ms:
		_last_click_slot = -1
		_last_click_time_ms = 0
		_try_open_split(slot_index)
		return
	_last_click_slot = slot_index
	_last_click_time_ms = now_ms

	# Toggle tooltip on single click (only if not dragging)
	_toggle_tooltip_for_slot(slot_index)

	# Selection is still used for click-to-equip bag fallback
	_selected_slot_index = slot_index

func _on_slot_release(_slot_index: int, global_pos: Vector2) -> void:
	if not _drag_active:
		return
	_finish_drag(global_pos)

# --- Drag logic ---

func _start_drag_from_slot(slot_index: int, _global_pos: Vector2) -> void:
	if _drag_active:
		return
	if player == null or not is_instance_valid(player):
		return

	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return
	var v: Variant = slots[slot_index]
	if v == null or not (v is Dictionary):
		return

	_drag_restore_snapshot = snap.duplicate(true)
	_drag_item = (v as Dictionary).duplicate(true)
	_drag_from_slot = slot_index
	_drag_from_bag = false
	_drag_from_bag_index = -1
	# Pick up: remove from source immediately.
	slots[slot_index] = null
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)

	_drag_active = true
	_drag_started = true
	_show_drag_visual()
	_hide_tooltip()
	_refresh()

func _finish_drag(global_pos: Vector2) -> void:
	if not _drag_active:
		return
	# If dragging a bag from equipment slot, only allow dropping into inventory slots or other bag slots.
	if _drag_from_bag:
		var inv_slot: int = _get_slot_index_under_global(global_pos)
		if inv_slot != -1:
			var ok: bool = false
			if player != null and is_instance_valid(player):
				ok = player.try_unequip_bag_to_inventory(_drag_from_bag_index, inv_slot)
			if not ok:
				bag_full_dialog.dialog_text = "can't move this bag (it may not be empty or there's no space)"
				bag_full_dialog.popup_centered()
			_end_drag()
			_refresh()
			return
		var bag_target: int = _get_bag_index_under_global(global_pos)
		if bag_target != -1 and player != null and is_instance_valid(player):
			player.try_move_or_swap_bag_slots(_drag_from_bag_index, bag_target)
		_end_drag()
		_refresh()
		return
	# Determine drop target
	var dropped: bool = false

	# 1) Drop onto inventory slot
	var target_slot: int = _get_slot_index_under_global(global_pos)
	if target_slot != -1:
		dropped = _drop_into_inventory_slot(target_slot)
	else:
		# 2) Drop onto bag equipment slot
		var bag_target: int = _get_bag_index_under_global(global_pos)
		if bag_target != -1:
			dropped = _drop_into_bag_slot(bag_target)
		else:
			# 3) Drop onto quick slot
			var q: int = _get_quick_index_under_global(global_pos)
			if q != -1:
				dropped = _drop_into_quick_slot(q)
			else:
				# 4) Drop onto equipment slot
				var equip_slot: String = _get_equipment_slot_under_global(global_pos)
				if equip_slot != "":
					dropped = _drop_into_equipment_slot(equip_slot)

	# 4.5) Drop onto merchant sell area
	if not dropped:
		var merchant_ui := get_tree().get_first_node_in_group("merchant_ui")
		if merchant_ui != null and merchant_ui.has_method("try_accept_inventory_drop"):
			var accepted: bool = bool(merchant_ui.call("try_accept_inventory_drop", global_pos, _drag_item))
			if accepted:
				_end_drag()
				return

	# 5) Drop outside: confirm delete
	if not dropped:
		if not _is_point_inside_panel(global_pos):
			_show_delete_confirm()
			return
		# If dropped inside panel but nowhere valid: restore to first free (or original if possible)
		_restore_drag_to_inventory()

	_end_drag()

func _end_drag() -> void:
	_drag_active = false
	_drag_from_slot = -1
	_drag_from_bag = false
	_drag_from_bag_index = -1
	_drag_item = {}
	_hide_drag_visual()
	_refresh()

func _cancel_drag_restore() -> void:
	# If a delete confirm is open, leave snapshot handling to it.
	pass

func _restore_drag_to_inventory() -> void:
	if player == null or not is_instance_valid(player):
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var preferred: int = _drag_from_slot
	# try preferred
	if preferred >= 0 and preferred < slots.size() and slots[preferred] == null:
		slots[preferred] = _drag_item
	else:
		var idx: int = _find_first_free_slot(slots)
		if idx != -1:
			slots[idx] = _drag_item
		else:
			# nowhere: restore snapshot
			player.apply_inventory_snapshot(_drag_restore_snapshot)
			return
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)

func _drop_into_inventory_slot(target_slot: int) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if target_slot < 0 or target_slot >= slots.size():
		return false

	var src: Dictionary = _drag_item
	var dst_v: Variant = slots[target_slot]
	if dst_v == null:
		slots[target_slot] = src
		snap["slots"] = slots
		player.apply_inventory_snapshot(snap)
		return true

	if dst_v is Dictionary:
		var dst: Dictionary = dst_v as Dictionary
		# Stack if same item and stackable
		var src_id: String = String(src.get("id", ""))
		var dst_id: String = String(dst.get("id", ""))
		if src_id != "" and src_id == dst_id:
			var max_stack: int = _get_stack_max(src_id)
			var dst_count: int = int(dst.get("count", 0))
			var src_count: int = int(src.get("count", 0))
			if max_stack > 1 and dst_count < max_stack:
				var can_add: int = min(src_count, max_stack - dst_count)
				dst["count"] = dst_count + can_add
				src_count -= can_add
				if src_count <= 0:
					# fully merged
					slots[target_slot] = dst
					snap["slots"] = slots
					player.apply_inventory_snapshot(snap)
					return true
				# partial: leave remainder in source -> move remainder to first free
				src["count"] = src_count
				slots[target_slot] = dst
				var free_idx := _find_first_free_slot(slots)
				if free_idx != -1:
					slots[free_idx] = src
					snap["slots"] = slots
					player.apply_inventory_snapshot(snap)
					return true
				# no free, revert and keep remainder by restoring to original
				player.apply_inventory_snapshot(_drag_restore_snapshot)
				return true

		# Otherwise swap
		slots[target_slot] = src
		# put dst back to source
		var back_idx: int = _drag_from_slot
		if back_idx >= 0 and back_idx < slots.size():
			if slots[back_idx] == null:
				slots[back_idx] = dst
			else:
				var free2 := _find_first_free_slot(slots)
				if free2 != -1:
					slots[free2] = dst
				else:
					player.apply_inventory_snapshot(_drag_restore_snapshot)
					return true
		snap["slots"] = slots
		player.apply_inventory_snapshot(snap)
		return true

	return false

func _drop_into_bag_slot(bag_index: int) -> bool:
	# Only accept bags; if not bag, return false to restore.
	var id: String = String(_drag_item.get("id", ""))
	if not _is_bag_item(id):
		return false
	if player == null or not is_instance_valid(player):
		return false
	# Equip: preferred slot is where it came from; player will consume from inventory slot,
	# but we already removed it into cursor. So we must place it back temporarily to that slot,
	# then call equip method. If slot occupied, we place into first free and use that as source.
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var src_idx: int = _drag_from_slot
	if src_idx < 0 or src_idx >= slots.size() or slots[src_idx] != null:
		src_idx = _find_first_free_slot(slots)
		if src_idx == -1:
			player.apply_inventory_snapshot(_drag_restore_snapshot)
			return true
	slots[src_idx] = _drag_item
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)
	var ok: bool = player.try_equip_bag_from_inventory_slot(src_idx, bag_index)
	if not ok:
		# revert if equip failed (bag not empty / invalid)
		player.apply_inventory_snapshot(_drag_restore_snapshot)
		return true
	return true

func _drop_into_quick_slot(q_index: int) -> bool:
	# Quick slot stores item_id (not slot index). Item stays in inventory.
	var id: String = String(_drag_item.get("id", ""))
	if id == "":
		return false
	if not _is_quick_allowed_item(id):
		_restore_drag_to_inventory()
		return true
	_restore_drag_to_inventory()
	_quick_refs[q_index] = id
	_refresh_quick_bar()
	return true

# --- Split logic ---

func _try_open_split(slot_index: int) -> void:
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
	_show_split(slot_index, count)

func _show_split(slot_index: int, count: int) -> void:
	_ensure_support_ui()
	_split_source_slot = slot_index
	_split_slider.min_value = 1
	_split_slider.max_value = count - 1
	_split_slider.value = int(clamp(int(count / 2.0), 1, count - 1))
	_update_split_label(count)
	_split_dialog.visible = true

func _hide_split() -> void:
	if _split_dialog != null:
		_split_dialog.visible = false
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
	var take: int = int(_split_slider.value)
	var remain: int = total - take
	_split_label.text = "Split: take %d / remain %d" % [take, remain]

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
	var take: int = int(_split_slider.value)
	if take < 1 or take >= total:
		_hide_split()
		return

	_drag_restore_snapshot = snap.duplicate(true)
	# Reduce source stack
	d["count"] = total - take
	slots[_split_source_slot] = d
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)

	# Put taken part into cursor drag item
	_drag_item = {"id": String(d.get("id", "")), "count": take}
	_drag_from_slot = -1
	_drag_active = true
	_show_drag_visual()
	_hide_split()
	_refresh()

func _on_split_cancel_pressed() -> void:
	_hide_split()

# --- Tooltip ---

func _toggle_tooltip_for_slot(slot_index: int) -> void:
	if _tooltip_for_slot == slot_index and _tooltip_panel != null and _tooltip_panel.visible:
		_hide_tooltip()
		return
	_show_tooltip_for_slot(slot_index)

func _show_tooltip_for_slot(slot_index: int) -> void:
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
	await _resize_tooltip_to_content()
	_tooltip_panel.visible = true
	_tooltip_for_slot = slot_index

	var mouse := get_viewport().get_mouse_position()
	_position_tooltip_left_of_point(mouse)

func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
	_tooltip_for_slot = -1


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
	var vp := get_viewport().get_visible_rect().size
	var size := _tooltip_panel.size
	var margin: float = 8.0
	# Default: to the left of point, align top to point
	var pos := Vector2(p.x - size.x - margin, p.y)
	# If outside left, clamp
	if pos.x < margin:
		pos.x = margin
	# If bottom overflow, try align bottom
	if pos.y + size.y > vp.y - margin:
		pos.y = p.y - size.y
	# Clamp top
	pos.y = clamp(pos.y, margin, vp.y - size.y - margin)
	_tooltip_panel.position = pos

# --- Delete confirm ---

func _show_delete_confirm() -> void:
	_ensure_support_ui()
	_delete_confirm.popup_centered()
	# keep drag active until user decides

func _on_delete_confirmed() -> void:
	# delete item: simply drop it (already removed from inventory)
	_end_drag()

func _on_delete_cancelled() -> void:
	_restore_drag_to_inventory()
	_end_drag()

# --- Settings ---

func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = not _settings_panel.visible

func _hide_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = false

func _on_settings_apply() -> void:
	var txt: String = _settings_input.text.strip_edges()
	var n: int = int(txt) if txt.is_valid_int() else 0
	if n <= 0:
		return
	var total: int = _get_total_inventory_slots()
	if total <= 0:
		return

	var target_cols: int = _grid_columns
	if _settings_mode.selected == 0:
		# Columns
		target_cols = max(1, n)
	else:
		# Rows -> columns derived
		var rows: int = max(1, n)
		target_cols = int(ceil(float(total) / float(rows)))
	target_cols = clamp(target_cols, 1, 20)

	# Before applying, verify the resized panel will remain fully visible when anchored at
	# the bottom-right point where you placed it in the scene.
	var ok_fit: bool = await _can_fit_columns(target_cols, total)
	if not ok_fit:
		# Do nothing (no message) if it would go off-screen.
		return

	_grid_columns = target_cols
	_save_grid_columns()
	# Mark layout dirty so the panel will be resized/anchored once (no repeated reflows).
	_layout_dirty = true
	_refresh()



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

func _measure_panel_size_for_columns(cols: int, total_slots: int) -> Vector2:
	# Measuring should not permanently mutate the live grid.
	var prev_cols: int = grid.columns
	var prev_grid_vis: bool = grid.visible
	# Ensure we have enough slot panels to measure accurately.
	_ensure_grid_child_count(total_slots)
	# Hide the grid while probing to avoid any visible "jump" when inventory is open.
	grid.visible = false
	grid.columns = max(1, cols)
	await get_tree().process_frame
	var grid_size: Vector2 = grid.get_combined_minimum_size()

	# Padding based on current layout in the scene (matches offsets in InventoryHUD.tscn)
	var pad_left: float = grid.position.x
	var pad_top: float = grid.position.y
	var pad_right: float = 16.0
	var pad_bottom: float = 16.0
	# Include header (gold label + settings button row)
	pad_top = min(pad_top, gold_label.position.y)
	var header_h: float = 50.0

	var size := Vector2(pad_left + grid_size.x + pad_right, header_h + grid_size.y + pad_bottom)
	# Restore previous grid columns to avoid visual jumps when a candidate doesn't apply.
	grid.columns = prev_cols
	grid.visible = prev_grid_vis
	return size

func _can_fit_columns(cols: int, total_slots: int) -> bool:
	if not _panel_anchor_valid:
		return true
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# Anchor must itself be on-screen for the "bottom-right fixed" guarantee to make sense.
	if _panel_anchor_br.x > vp_size.x or _panel_anchor_br.y > vp_size.y:
		return false
	var size: Vector2 = await _measure_panel_size_for_columns(cols, total_slots)
	var new_pos: Vector2 = _panel_anchor_br - size
	return new_pos.x >= 0.0 and new_pos.y >= 0.0

func _ensure_columns_fit_view(total_slots: int) -> void:
	# If the current grid layout would push the panel off-screen, automatically choose a
	# nearby columns value that fits so the settings button stays reachable.
	if not _panel_anchor_valid:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if _panel_anchor_br.x > vp_size.x or _panel_anchor_br.y > vp_size.y:
		return

	var current: int = clamp(_grid_columns, 1, 20)
	var best: int = current
	var best_delta: int = 999
	for c in range(1, 21):
		var fits: bool = await _can_fit_columns(c, total_slots)
		if not fits:
			continue
		var d: int = abs(c - current)
		if d < best_delta:
			best_delta = d
			best = c
		elif d == best_delta and c > best:
			# Prefer a slightly wider grid if equally close (usually reduces height).
			best = c

	if best != current:
		_grid_columns = best
		_save_grid_columns()

func _on_settings_sort() -> void:
	_sort_inventory_slots()
	_refresh()

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
	_refresh()


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
	if _tooltip_for_slot < 0:
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
	_refresh()

func _on_tooltip_equip_pressed() -> void:
	if player == null or not is_instance_valid(player):
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
	if not _is_equippable_item(id):
		return
	var target_slot: String = _get_default_equip_slot(id)
	if target_slot == "":
		return
	if player.has_method("try_equip_from_inventory_slot"):
		var ok: bool = bool(player.call("try_equip_from_inventory_slot", _tooltip_for_slot, target_slot))
		if ok:
			_hide_tooltip()
			_refresh()
		else:
			_show_equip_fail_toast()

func _on_tooltip_sell_pressed() -> void:
	if not _trade_open:
		return
	if player == null or not is_instance_valid(player):
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
	if id == "":
		return
	var total: int = _get_total_item_count(id)
	if total <= 0:
		return
	var merchant_ui := get_tree().get_first_node_in_group("merchant_ui")
	if merchant_ui == null:
		return
	if total <= 1 or _get_stack_max(id) <= 1:
		if merchant_ui.has_method("sell_items_from_inventory"):
			merchant_ui.call("sell_items_from_inventory", id, 1)
		_hide_tooltip()
		_refresh()
		return
	if merchant_ui.has_method("request_sell_from_inventory"):
		merchant_ui.call("request_sell_from_inventory", id, total)
	_hide_tooltip()
	_refresh()


func _show_consumable_fail_toast(reason: String, item_id: String) -> void:
	_ensure_support_ui()
	if _toast_label == null:
		return
	var msg: String = ""
	match reason:
		"hp_full":
			msg = "Здоровье полно"
		"mp_full":
			msg = "Мана полна"
		"hpmp_full":
			msg = "Здоровье и мана полны"
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
			msg = "Не подходящий уровень предмета"
		"skill":
			msg = "Вы не умеете пользоваться этим"
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




func _start_quick_drag(q_index: int) -> void:
	if q_index < 0 or q_index >= _quick_refs.size():
		return
	if player == null or not is_instance_valid(player):
		return
	var item_id: String = _quick_refs[q_index]
	if item_id == "":
		return
	# Build drag item purely for visual purposes (count = total in inventory)
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var total: int = 0
	for v in slots:
		if v is Dictionary and String((v as Dictionary).get("id","")) == item_id:
			total += int((v as Dictionary).get("count", 0))
	if total <= 0:
		_quick_refs[q_index] = ""
		_refresh_quick_bar()
		return
	_quick_drag_active = true
	_quick_drag_index = q_index
	_quick_drag_item = {"id": item_id, "count": total}
	_show_drag_visual()

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
	await get_tree().process_frame
	if String(text).strip_edges() == "" or float(_tooltip_label.get_content_height()) <= 1.0:
		await get_tree().process_frame
		if String(text).strip_edges() == "" or float(_tooltip_label.get_content_height()) <= 1.0:
			return
	await _resize_tooltip_to_content()
	_tooltip_panel.visible = true
	_tooltip_for_slot = -999
	var mouse := get_viewport().get_mouse_position()
	_position_tooltip_left_of_point(mouse)

# --- Refresh & render ---

func _refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("get_inventory_snapshot"):
		return

	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var bag_slots: Array = snap.get("bag_slots", [])
	var total_slots: int = slots.size()

	# Mark layout dirty only when geometry changes.
	if total_slots != _last_total_slots:
		_last_total_slots = total_slots
		_layout_dirty = true
	if _grid_columns != _last_applied_columns:
		_layout_dirty = true

	# Ensure grid children exist, but don't reflow unless necessary.
	_ensure_grid_child_count(total_slots)
	_hook_slot_panels()

	# Apply/rescale panel only when required (startup / apply settings / bag slots change).
	if _layout_dirty and not _layout_recalc_in_progress:
		await _apply_inventory_layout(total_slots)

	# Gold
	gold_label.text = "Gold: %s" % _format_money_bronze(int(snap.get("gold", 0)))

	# Render items
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null or not slot_panel.visible:
			continue
		_render_slot(slot_panel, i, slots)

	_update_bag_buttons(bag_slots)
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

func show_bag_full(message: String = "Your bags are full!") -> void:
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

func _get_bag_index_under_global(global_pos: Vector2) -> int:
	for bi in range(4):
		var btn := _get_bag_button_for_logical(bi)
		if btn != null and btn.get_global_rect().has_point(global_pos):
			return bi
	return -1

func _get_quick_index_under_global(global_pos: Vector2) -> int:
	if _quick_bar == null:
		return -1
	for i in range(_quick_buttons.size()):
		var b := _quick_buttons[i]
		if b != null and b.get_global_rect().has_point(global_pos):
			return i
	return -1

func _get_equipment_slot_under_global(global_pos: Vector2) -> String:
	var hud := get_tree().get_first_node_in_group("character_hud")
	if hud != null and hud.has_method("get_equipment_slot_at_global_pos"):
		return String(hud.call("get_equipment_slot_at_global_pos", global_pos))
	return ""

func try_handle_equipment_drop(global_pos: Vector2, slot_id: String) -> bool:
	if not _is_open:
		return false
	if player == null or not is_instance_valid(player):
		return false
	var inv_slot := _get_slot_index_under_global(global_pos)
	if inv_slot == -1:
		return false
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	if inv_slot >= slots.size() or slots[inv_slot] != null:
		return false
	var equip: Node = player.get_node_or_null("Components/Equipment")
	if equip != null and equip.has_method("try_unequip_to_inventory"):
		return bool(equip.call("try_unequip_to_inventory", slot_id, inv_slot))
	return false

func _drop_into_equipment_slot(slot_id: String) -> bool:
	var id: String = String(_drag_item.get("id", ""))
	if not _is_equippable_item(id):
		return false
	if player == null or not is_instance_valid(player):
		return false
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var src_idx: int = _drag_from_slot
	if src_idx < 0 or src_idx >= slots.size() or slots[src_idx] != null:
		src_idx = _find_first_free_slot(slots)
		if src_idx == -1:
			player.apply_inventory_snapshot(_drag_restore_snapshot)
			return true
	slots[src_idx] = _drag_item
	snap["slots"] = slots
	player.apply_inventory_snapshot(snap)
	if player.has_method("try_equip_from_inventory_slot"):
		var ok: bool = bool(player.call("try_equip_from_inventory_slot", src_idx, slot_id))
		if not ok:
			player.apply_inventory_snapshot(_drag_restore_snapshot)
			_show_equip_fail_toast()
			return true
	return true

func _build_tooltip_text(id: String, count: int) -> String:
	var db := get_node_or_null("/root/DataDB")
	var meta: Dictionary = {}
	if db != null and db.has_method("get_item"):
		meta = db.call("get_item", id) as Dictionary
	return TOOLTIP_BUILDER.build_item_tooltip(meta, count, player)


func _rarity_color_hex(rarity: String, typ: String) -> String:
	var r := rarity.to_lower()
	if r == "" and typ == "junk":
		r = "junk"
	match r:
		"junk":
			return "#8a8a8a"
		"common":
			return "#ffffff"
		"uncommon":
			return "#3bdc3b"
		"rare":
			return "#4aa3ff"
		"epic":
			return "#a335ee"
		"legendary":
			return "#ff8000"
		_:
			return "#ffffff"


func _format_consumable_effects(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var instant: bool = bool(c.get("instant", false))
	# Potions typically use hp/mp, food/drink uses hp_total/mp_total over duration.
	if instant:
		var hp: int = int(c.get("hp", 0))
		var mp: int = int(c.get("mp", 0))
		if hp > 0:
			out.append("restores %d hp" % hp)
		if mp > 0:
			out.append("restores %d mp" % mp)
	else:
		var dur: int = int(c.get("duration_sec", 0))
		var hp_t: int = int(c.get("hp_total", 0))
		var mp_t: int = int(c.get("mp_total", 0))
		if hp_t > 0:
			if dur > 0:
				out.append("restores %d hp over %ds" % [hp_t, dur])
			else:
				out.append("restores %d hp" % hp_t)
		if mp_t > 0:
			if dur > 0:
				out.append("restores %d mp over %ds" % [mp_t, dur])
			else:
				out.append("restores %d mp" % mp_t)
	return out


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

	# Refill slots sequentially, keep same total size
	for i in range(slots.size()):
		slots[i] = null
	for i in range(min(slots.size(), items.size())):
		slots[i] = items[i]
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
		if _tooltip_panel != null:
			_tooltip_panel.visible = false
			_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	if _delete_confirm == null:
		_delete_confirm = ConfirmationDialog.new()
		_delete_confirm.name = "DeleteConfirm"
		_delete_confirm.dialog_text = "Delete this item?"
		add_child(_delete_confirm)
		_delete_confirm.confirmed.connect(_on_delete_confirmed)
		_delete_confirm.canceled.connect(_on_delete_cancelled)

	if _split_dialog == null:
		_split_dialog = Panel.new()
		_split_dialog.name = "SplitDialog"
		_split_dialog.visible = false
		add_child(_split_dialog)
		_split_dialog.size = Vector2(260, 110)
		_split_dialog.position = Vector2(40, 40)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(0,0,0,0.8)
		sb2.content_margin_left = 10
		sb2.content_margin_right = 10
		sb2.content_margin_top = 10
		sb2.content_margin_bottom = 10
		_split_dialog.add_theme_stylebox_override("panel", sb2)

		_split_label = Label.new()
		_split_dialog.add_child(_split_label)
		_split_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_split_label.offset_left = 0
		_split_label.offset_top = 0
		_split_label.offset_right = 0
		_split_label.offset_bottom = 20

		_split_slider = HSlider.new()
		_split_dialog.add_child(_split_slider)
		_split_slider.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_split_slider.offset_left = 0
		_split_slider.offset_top = 28
		_split_slider.offset_right = 0
		_split_slider.offset_bottom = 52
		_split_slider.value_changed.connect(_on_split_value_changed)

		_split_ok = Button.new()
		_split_ok.text = "OK"
		_split_dialog.add_child(_split_ok)
		_split_ok.position = Vector2(0, 60)
		_split_ok.pressed.connect(_on_split_ok_pressed)

		_split_cancel = Button.new()
		_split_cancel.text = "Cancel"
		_split_dialog.add_child(_split_cancel)
		_split_cancel.position = Vector2(90, 60)
		_split_cancel.pressed.connect(_on_split_cancel_pressed)

	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.name = "CenterToast"
		_toast_label.visible = false
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_toast_label)
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

	if _settings_button == null:
		_settings_button = Button.new()
		_settings_button.name = "InvSettingsButton"
		_settings_button.text = "⋮"
		_settings_button.size = Vector2(28, 28)
		panel.add_child(_settings_button)
		_settings_button.position = Vector2(panel.size.x - 34, 6)
		_settings_button.pressed.connect(_toggle_settings)

	if _settings_panel == null:
		_settings_panel = Panel.new()
		_settings_panel.name = "InvSettingsPanel"
		_settings_panel.visible = false
		panel.add_child(_settings_panel)
		_settings_panel.position = Vector2(panel.size.x - 200, 36)
		_settings_panel.size = Vector2(190, 120)
		var sb3 := StyleBoxFlat.new()
		sb3.bg_color = Color(0,0,0,0.85)
		sb3.content_margin_left = 8
		sb3.content_margin_right = 8
		sb3.content_margin_top = 8
		sb3.content_margin_bottom = 8
		_settings_panel.add_theme_stylebox_override("panel", sb3)

		_settings_mode = OptionButton.new()
		_settings_mode.add_item("Columns", 0)
		_settings_mode.add_item("Rows", 1)
		_settings_panel.add_child(_settings_mode)
		_settings_mode.position = Vector2(8, 8)
		_settings_mode.size = Vector2(90, 26)

		_settings_input = LineEdit.new()
		_settings_input.placeholder_text = "number"
		_settings_panel.add_child(_settings_input)
		_settings_input.position = Vector2(105, 8)
		_settings_input.size = Vector2(70, 26)

		_settings_apply = Button.new()
		_settings_apply.text = "Apply"
		_settings_panel.add_child(_settings_apply)
		_settings_apply.position = Vector2(8, 44)
		_settings_apply.size = Vector2(80, 26)
		_settings_apply.pressed.connect(_on_settings_apply)

		_settings_sort = Button.new()
		_settings_sort.text = "Sort"
		_settings_panel.add_child(_settings_sort)
		_settings_sort.position = Vector2(95, 44)
		_settings_sort.size = Vector2(80, 26)
		_settings_sort.pressed.connect(_on_settings_sort)

	# Quick bar is part of the scene (InventoryHUD.tscn) so you can edit it visually.
	if _quick_bar == null:
		_quick_bar = get_node_or_null("QuickBar") as VBoxContainer
		if _quick_bar == null:
			# Fallback (should not happen, but keeps project from breaking if node is removed).
			_quick_bar = VBoxContainer.new()
			_quick_bar.name = "QuickBar"
			add_child(_quick_bar)
			_quick_bar.position = Vector2(10, 10)
			_quick_bar.size = Vector2(44, 220)
		# Collect or create 5 buttons
		_quick_buttons = []
		var kids := _quick_bar.get_children()
		for i in range(min(5, kids.size())):
			var b := kids[i] as Button
			if b != null:
				_quick_buttons.append(b)
		while _quick_buttons.size() < 5:
			var nb := Button.new()
			nb.text = ""
			nb.custom_minimum_size = Vector2(24, 24)
			_quick_bar.add_child(nb)
			_quick_buttons.append(nb)
		for i in range(5):
			var b := _quick_buttons[i]
			b.text = ""
			b.expand_icon = true
			_ensure_quick_button_visuals(b)
			b.pressed.connect(_on_quick_pressed.bind(i))
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

func _refresh_quick_bar() -> void:
	if _quick_buttons.size() != 5:
		return
	if player == null:
		return
	var snap: Dictionary = player.get_inventory_snapshot()
	var slots: Array = snap.get("slots", [])
	var db := get_node_or_null("/root/DataDB")
	for i in range(5):
		var b := _quick_buttons[i]
		var item_id: String = _quick_refs[i]
		if item_id == "":
			b.icon = null
			b.text = ""
			_update_quick_cooldown(b, "")
			continue
		# Sum counts across all stacks in inventory
		var total: int = 0
		for v in slots:
			if v is Dictionary and String((v as Dictionary).get("id","")) == item_id:
				total += int((v as Dictionary).get("count", 0))
		# If the player is currently dragging this item, it may be temporarily removed from slots.
		# Keep quick slot stable during drag so it doesn't get cleared.
		if total <= 0 and _drag_active and String(_drag_item.get("id", "")) == item_id:
			total = int(_drag_item.get("count", 0))
		if total <= 0:
			# Item no longer present; clear quick slot
			_quick_refs[i] = ""
			b.icon = null
			b.text = ""
			continue
		var meta: Dictionary = db.call("get_item", item_id) as Dictionary if db != null and db.has_method("get_item") else {}
		var icon_path: String = String(meta.get("icon", meta.get("icon_path","")))
		b.icon = _get_icon_texture(icon_path)
		b.text = str(total) if total > 1 else ""
		_update_quick_cooldown(b, item_id)


func _update_panel_size_to_fit_grid(_total_slots: int) -> void:
	# Make the background panel resize to fully contain the grid.
	# We keep bottom-right stable via _refresh_layout_anchor().
	if panel == null or grid == null:
		return
	# Ensure grid has correct column count before measuring.
	grid.columns = max(1, _grid_columns)
	await get_tree().process_frame
	var grid_size: Vector2 = grid.get_combined_minimum_size()
	# Padding based on current layout in the scene (matches offsets in InventoryHUD.tscn)
	var pad_left: float = grid.position.x
	var pad_top: float = grid.position.y
	var pad_right: float = 16.0
	var pad_bottom: float = 16.0
	# Include header (gold label + settings button row)
	pad_top = min(pad_top, gold_label.position.y)
	var header_h: float = 50.0
	# Resize grid and panel
	grid.size = grid_size
	var new_size := Vector2(pad_left + grid_size.x + pad_right, header_h + grid_size.y + pad_bottom)
	panel.custom_minimum_size = new_size
	panel.size = new_size
	# Keep the settings UI pinned to the panel's top-right corner.
	var m: float = 6.0
	if _settings_button != null:
		_settings_button.position = Vector2(panel.size.x - _settings_button.size.x - m, m)
	if _settings_panel != null:
		_settings_panel.position = Vector2(panel.size.x - _settings_panel.size.x - m, m + 30.0)

func _apply_inventory_layout(total_slots: int) -> void:
	# Recalculate grid columns (fit) + panel size + anchoring, but only when needed.
	if panel == null or grid == null:
		return
	_layout_recalc_in_progress = true
	var was_vis: bool = panel.visible
	# Hide panel during reflow to avoid visible "jump".
	if was_vis:
		panel.visible = false
	await _ensure_columns_fit_view(total_slots)
	grid.columns = max(1, _grid_columns)
	await _update_panel_size_to_fit_grid(total_slots)
	await _refresh_layout_anchor()
	_last_applied_columns = _grid_columns
	_layout_dirty = false
	_layout_recalc_in_progress = false
	if was_vis:
		await get_tree().process_frame
		panel.visible = true

func _refresh_layout_anchor() -> void:
	# Keep bottom-right of inventory panel stable, grow up + left (towards screen center).
	# Capture anchor if it wasn't set yet (normally set in _ready from scene placement).
	if not _panel_anchor_valid:
		var rect := panel.get_global_rect()
		_panel_anchor_br = rect.position + rect.size
		_panel_anchor_valid = true
	# After content changes, re-anchor
	await get_tree().process_frame
	var rect2 := panel.get_global_rect()
	var new_pos := _panel_anchor_br - rect2.size
	# Clamp so panel can't go off the bottom/right edges.
	# InventoryHUD isn't necessarily a Control, so get_viewport_rect() may not exist.
	# Use the Viewport's visible rect instead.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	new_pos.x = clamp(new_pos.x, 0.0, vp_size.x - rect2.size.x)
	new_pos.y = clamp(new_pos.y, 0.0, vp_size.y - rect2.size.y)
	panel.global_position = new_pos

func _show_drag_visual() -> void:
	if not has_node("DragIcon"):
		var drag_icon := TextureRect.new()
		drag_icon.name = "DragIcon"
		drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(drag_icon)
		drag_icon.z_index = 999
	_update_drag_visual()
	get_node("DragIcon").visible = true

func _hide_drag_visual() -> void:
	var drag_icon := get_node_or_null("DragIcon") as TextureRect
	if drag_icon != null:
		drag_icon.visible = false

func _update_drag_visual() -> void:
	var drag_icon := get_node_or_null("DragIcon") as TextureRect
	if drag_icon == null:
		return
	var src: Dictionary = _drag_item if _drag_active else _quick_drag_item
	var id: String = String(src.get("id",""))
	var db := get_node_or_null("/root/DataDB")
	var icon_path: String = ""
	if db != null and db.has_method("get_item"):
		var meta: Dictionary = db.call("get_item", id) as Dictionary
		icon_path = String(meta.get("icon", meta.get("icon_path","")))
	drag_icon.texture = _get_icon_texture(icon_path)
	drag_icon.size = Vector2(36, 36)
	var m := get_viewport().get_mouse_position()
	drag_icon.position = m + Vector2(12, 12)

func _format_money_bronze(bronze: int) -> String:
	bronze = max(0, bronze)
	var gold: int = int(bronze / 10000.0)
	var silver: int = int((bronze % 10000) / 100.0)
	var bronze_small: int = int(bronze % 100)
	var parts: Array[String] = []
	if gold > 0:
		parts.append("%dg" % gold)
	if silver > 0 or gold > 0:
		parts.append("%ds" % silver)
	parts.append("%db" % bronze_small)
	return " ".join(parts)
