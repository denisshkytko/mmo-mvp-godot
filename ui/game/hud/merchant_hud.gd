extends CanvasLayer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")

const BUY_PRICE_MULTIPLIER: float = 1.25
const DRAG_THRESHOLD: float = 8.0

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Title
@onready var tabs: TabContainer = $Panel/Tabs
@onready var buy_scroll: ScrollContainer = $Panel/Tabs/Покупка/Scroll
@onready var sell_scroll: ScrollContainer = $Panel/Tabs/Продажа/Scroll
@onready var buy_grid: GridContainer = $Panel/Tabs/Покупка/Scroll/Grid
@onready var sell_grid: GridContainer = $Panel/Tabs/Продажа/Scroll/Grid

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_label: RichTextLabel = $TooltipPanel/Margin/VBox/Text
@onready var tooltip_use_btn: Button = $TooltipPanel/Margin/VBox/UseButton
@onready var tooltip_equip_btn: Button = $TooltipPanel/Margin/VBox/EquipButton
@onready var tooltip_unequip_btn: Button = $TooltipPanel/Margin/VBox/UnequipButton

var _player: Node = null
var _merchant: Node = null
var _is_open: bool = false

var _buy_entries: Array[Dictionary] = []
var _sell_entries: Array[Dictionary] = []

var _icon_cache: Dictionary = {}
var _tooltip_item_id: String = ""

# Drag state for buy tab
var _drag_active: bool = false
var _drag_pending: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_item_id: String = ""
var _drag_item_count: int = 0
var _drag_item_icon: Texture2D = null
var _drag_visual: TextureRect = null

# Quantity dialog
var _qty_dialog: Panel = null
var _qty_slider: HSlider = null
var _qty_label: Label = null
var _qty_ok: Button = null
var _qty_cancel: Button = null
var _qty_callback: Callable = Callable()
var _qty_max: int = 1
var _qty_title: String = ""

# Sell refresh
var _sell_refresh_accum: float = 0.0

func _ready() -> void:
	panel.visible = false
	tooltip_panel.visible = false
	if tooltip_use_btn != null:
		tooltip_use_btn.visible = false
	if tooltip_equip_btn != null:
		tooltip_equip_btn.visible = false
	if tooltip_unequip_btn != null:
		tooltip_unequip_btn.visible = false
	_ensure_qty_dialog()

func is_open() -> bool:
	return _is_open

func toggle_for_merchant(merchant_node: Node) -> void:
	if _is_open and _merchant == merchant_node:
		close()
		return
	open_for_merchant(merchant_node)

func open_for_merchant(merchant_node: Node) -> void:
	_merchant = merchant_node
	_player = NodeCache.get_player(get_tree())
	_is_open = true
	panel.visible = true
	if title_label != null:
		var t: String = ""
		if _merchant != null and _merchant.has_method("get_merchant_title"):
			t = String(_merchant.call("get_merchant_title"))
		title_label.text = t if t != "" else "Торговля"
	_load_buy_entries()
	_refresh_buy_grid()
	_refresh_sell_grid()
	_sync_inventory_trade_state(true)

func close() -> void:
	_is_open = false
	panel.visible = false
	_hide_tooltip()
	_stop_drag()
	_sync_inventory_trade_state(false)
	_merchant = null

func _process(delta: float) -> void:
	if not _is_open:
		return
	if _merchant != null and not is_instance_valid(_merchant):
		close()
		return
	if _drag_active:
		_update_drag_visual()
	_sell_refresh_accum += delta
	if _sell_refresh_accum >= 1.0:
		_sell_refresh_accum = 0.0
		_refresh_sell_grid()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if _drag_pending and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _drag_active:
				_finish_drag(mb.global_position)
			_stop_drag()
			_drag_pending = false
	elif _drag_active and event is InputEventScreenTouch:
		if not (event as InputEventScreenTouch).pressed:
			_finish_drag((event as InputEventScreenTouch).position)
			_stop_drag()
	elif tooltip_panel != null and tooltip_panel.visible:
		if event is InputEventMouseButton:
			var mb2 := event as InputEventMouseButton
			if mb2.button_index == MOUSE_BUTTON_LEFT and mb2.pressed:
				_hide_tooltip()
		elif event is InputEventScreenTouch:
			if (event as InputEventScreenTouch).pressed:
				_hide_tooltip()

func try_accept_inventory_drop(global_pos: Vector2, item: Dictionary) -> bool:
	if not _is_open:
		return false
	if not _is_sell_tab_active():
		return false
	if item.is_empty():
		return false
	if not _is_point_over_sell_area(global_pos):
		return false
	var id: String = String(item.get("id", ""))
	var count: int = int(item.get("count", 0))
	if id == "" or count <= 0:
		return false
	_sell_dragged_item(id, count)
	return true

func _sync_inventory_trade_state(state: bool) -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("set_trade_open"):
		inv_ui.call("set_trade_open", state)
	if not state and inv_ui != null and inv_ui.has_method("hide_tooltip"):
		inv_ui.call("hide_tooltip")

func _load_buy_entries() -> void:
	_buy_entries.clear()
	if _merchant == null:
		return
	var preset: Resource = null
	if _merchant.has_method("get_merchant_preset"):
		preset = _merchant.call("get_merchant_preset")
	elif "merchant_preset" in _merchant:
		preset = _merchant.get("merchant_preset")
	var fallback := preload("res://core/trade/presets/merchant_preset_level_1.tres")
	if preset == null:
		preset = fallback
	_append_entries_from_preset(preset)
	if _buy_entries.is_empty() and preset != fallback:
		_append_entries_from_preset(fallback)

func _append_entries_from_preset(preset: Resource) -> void:
	if preset == null:
		return
	if preset.has_method("get_entries"):
		var entries: Array = preset.call("get_entries")
		for v in entries:
			if v == null:
				continue
			if v.has_method("get"):
				var item_id: String = String(v.get("item_id", ""))
				var count: int = int(v.get("count", 1))
				if item_id != "" and count > 0:
					_buy_entries.append({"id": item_id, "count": count})
	else:
		var arr: Array = preset.get("items") if ("items" in preset) else []
		for v in arr:
			if v is Dictionary:
				var d: Dictionary = v as Dictionary
				var item_id2: String = String(d.get("item_id", ""))
				var count2: int = int(d.get("count", 1))
				if item_id2 != "" and count2 > 0:
					_buy_entries.append({"id": item_id2, "count": count2})

func _refresh_buy_grid() -> void:
	for child in buy_grid.get_children():
		child.queue_free()
	for entry in _buy_entries:
		var item_id: String = String(entry.get("id", ""))
		var count: int = int(entry.get("count", 1))
		if item_id == "" or count <= 0:
			continue
		var cell := _build_item_cell(item_id, count, "Купить", true)
		buy_grid.add_child(cell)

func _refresh_sell_grid() -> void:
	for child in sell_grid.get_children():
		child.queue_free()
	_sell_entries.clear()
	if _merchant == null or _player == null:
		return
	if _merchant.has_method("get_merchant_sales_for_player"):
		var arr: Array = _merchant.call("get_merchant_sales_for_player", _player.get_instance_id())
		for entry in arr:
			if entry is Dictionary:
				var d: Dictionary = entry as Dictionary
				var item_id: String = String(d.get("id", ""))
				var count: int = int(d.get("count", 0))
				var sale_id: int = int(d.get("sale_id", -1))
				if item_id != "" and count > 0 and sale_id != -1:
					_sell_entries.append({"id": item_id, "count": count, "sale_id": sale_id})
	for entry2 in _sell_entries:
		var item_id2: String = String(entry2.get("id", ""))
		var count2: int = int(entry2.get("count", 1))
		var sale_id2: int = int(entry2.get("sale_id", -1))
		if item_id2 == "" or count2 <= 0:
			continue
		var cell2 := _build_item_cell(item_id2, count2, "Выкупить", false, sale_id2)
		sell_grid.add_child(cell2)

func _build_item_cell(item_id: String, count: int, action_text: String, is_buy: bool, sale_id: int = -1) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(240, 50)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_FILL

	var padding := MarginContainer.new()
	padding.set_anchors_preset(Control.PRESET_FULL_RECT)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_left", 6)
	padding.add_theme_constant_override("margin_right", 6)
	padding.add_theme_constant_override("margin_top", 4)
	padding.add_theme_constant_override("margin_bottom", 4)
	cell.add_child(padding)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_child(row)

	var icon_panel := Panel.new()
	icon_panel.custom_minimum_size = Vector2(32, 32)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_panel)

	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_panel.add_child(icon)
	icon.texture = _get_item_icon(item_id)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.text = _format_item_label(item_id, count)
	row.add_child(name_label)

	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(80, 40)
	action_button.text = action_text
	row.add_child(action_button)

	icon_panel.gui_input.connect(_on_item_tooltip_input.bind(item_id, count))
	name_label.gui_input.connect(_on_item_tooltip_input.bind(item_id, count))

	if is_buy:
		action_button.pressed.connect(_on_buy_button_pressed.bind(item_id, count))
		cell.gui_input.connect(_on_buy_cell_input.bind(item_id, count))
	else:
		action_button.pressed.connect(_on_buyback_button_pressed.bind(item_id, count, sale_id))

	return cell

func _format_item_label(item_id: String, count: int) -> String:
	var db := get_node_or_null("/root/DataDB")
	var name: String = item_id
	if db != null and db.has_method("get_item_name"):
		name = String(db.call("get_item_name", item_id))
	if count > 1:
		return "%s x%d" % [name, count]
	return name

func _on_item_tooltip_input(event: InputEvent, item_id: String, count: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		_toggle_tooltip(item_id, count, mb.global_position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			return
		_toggle_tooltip(item_id, count, st.position)

func _toggle_tooltip(item_id: String, count: int, global_pos: Vector2) -> void:
	if tooltip_panel != null and tooltip_panel.visible and _tooltip_item_id == item_id:
		_hide_tooltip()
		return
	_show_tooltip(item_id, count, global_pos)

func _on_buy_cell_input(event: InputEvent, item_id: String, count: int) -> void:
	if not _is_buy_tab_active():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_pending = true
				_drag_start_pos = mb.position
				_drag_item_id = item_id
				_drag_item_count = count
				_drag_item_icon = _get_item_icon(item_id)
			else:
				if _drag_active:
					_finish_drag(mb.global_position)
				_stop_drag()
				_drag_pending = false
	elif event is InputEventMouseMotion and _drag_pending:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start_pos) >= DRAG_THRESHOLD:
			_start_drag()

func _start_drag() -> void:
	if _drag_item_id == "" or _drag_item_count <= 0:
		_drag_pending = false
		return
	_drag_active = true
	_show_drag_visual()
	_hide_tooltip()

func _stop_drag() -> void:
	_drag_active = false
	_drag_pending = false
	_drag_item_id = ""
	_drag_item_count = 0
	_drag_item_icon = null
	_hide_drag_visual()

func _show_drag_visual() -> void:
	if _drag_visual == null:
		_drag_visual = TextureRect.new()
		_drag_visual.name = "DragVisual"
		_drag_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_drag_visual)
		_drag_visual.z_index = 200
	_drag_visual.texture = _drag_item_icon
	_drag_visual.custom_minimum_size = Vector2(40, 40)
	_drag_visual.size = Vector2(40, 40)
	_drag_visual.visible = true
	_update_drag_visual()

func _update_drag_visual() -> void:
	if _drag_visual == null:
		return
	var pos := get_viewport().get_mouse_position()
	_drag_visual.global_position = pos + Vector2(12, 12)

func _hide_drag_visual() -> void:
	if _drag_visual != null:
		_drag_visual.visible = false

func _finish_drag(global_pos: Vector2) -> void:
	if not _drag_active:
		return
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("is_point_over_inventory"):
		var over: bool = bool(inv_ui.call("is_point_over_inventory", global_pos))
		if over:
			_try_buy_item(_drag_item_id, _drag_item_count)

func _on_buy_button_pressed(item_id: String, count: int) -> void:
	if count <= 1:
		_try_buy_item(item_id, 1)
		return
	_show_quantity_dialog(count, "Купить")
	_qty_callback = Callable(self, "_on_buy_quantity_selected").bind(item_id)

func _on_buy_quantity_selected(amount: int, item_id: String) -> void:
	_try_buy_item(item_id, amount)

func request_sell_from_inventory(item_id: String, max_count: int) -> void:
	if max_count <= 1:
		sell_items_from_inventory(item_id, 1)
		return
	_show_quantity_dialog(max_count, "Продать")
	_qty_callback = Callable(self, "_on_sell_quantity_selected").bind(item_id)

func _on_sell_quantity_selected(amount: int, item_id: String) -> void:
	sell_items_from_inventory(item_id, amount)

func _on_buyback_button_pressed(item_id: String, count: int, sale_id: int) -> void:
	if sale_id == -1:
		return
	_try_buyback_item(item_id, count, sale_id)

func _try_buy_item(item_id: String, count: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if count <= 0:
		return
	var price_per: int = _get_buy_price(item_id)
	var total_price: int = price_per * count
	if not _has_gold(total_price):
		_notify_not_enough_gold()
		return
	if not _can_fit_item(item_id, count):
		_notify_bag_full()
		return
	var remaining: int = int(_player.call("add_item", item_id, count))
	if remaining > 0:
		_player.call("consume_item", item_id, count - remaining)
		_notify_bag_full()
		return
	_player.call("add_gold", -total_price)

func _try_buyback_item(item_id: String, count: int, sale_id: int) -> void:
	if _merchant == null or _player == null or not is_instance_valid(_player):
		return
	var price_per: int = _get_base_price(item_id)
	var total_price: int = price_per * count
	if not _has_gold(total_price):
		_notify_not_enough_gold()
		return
	if not _can_fit_item(item_id, count):
		_notify_bag_full()
		return
	if _merchant.has_method("take_merchant_sale"):
		var taken: Dictionary = _merchant.call("take_merchant_sale", _player.get_instance_id(), sale_id)
		if taken.is_empty():
			return
		var remaining: int = int(_player.call("add_item", item_id, count))
		if remaining > 0:
			_player.call("consume_item", item_id, count - remaining)
			_notify_bag_full()
			return
		_player.call("add_gold", -total_price)
		_refresh_sell_grid()

func sell_items_from_inventory(item_id: String, count: int) -> void:
	if _player == null or _merchant == null:
		return
	if count <= 0:
		return
	var removed: int = 0
	if _player.has_method("consume_item"):
		removed = int(_player.call("consume_item", item_id, count))
	if removed <= 0:
		return
	var gold_gain: int = _get_base_price(item_id) * removed
	_player.call("add_gold", gold_gain)
	if _merchant.has_method("add_merchant_sale"):
		_merchant.call("add_merchant_sale", _player.get_instance_id(), item_id, removed)
	_refresh_sell_grid()

func _sell_dragged_item(item_id: String, count: int) -> void:
	if _player == null or _merchant == null:
		return
	var gold_gain: int = _get_base_price(item_id) * count
	_player.call("add_gold", gold_gain)
	if _merchant.has_method("add_merchant_sale"):
		_merchant.call("add_merchant_sale", _player.get_instance_id(), item_id, count)
	_refresh_sell_grid()

func _has_gold(cost: int) -> bool:
	if _player == null:
		return false
	if not _player.has_method("get_inventory_snapshot"):
		return false
	var snap: Dictionary = _player.call("get_inventory_snapshot") as Dictionary
	var gold: int = int(snap.get("gold", 0))
	return gold >= cost

func _can_fit_item(item_id: String, count: int) -> bool:
	if _player == null or not _player.has_method("get_inventory_snapshot"):
		return false
	var snap: Dictionary = _player.call("get_inventory_snapshot") as Dictionary
	var slots: Array = snap.get("slots", [])
	var max_stack: int = _get_stack_max(item_id)
	var capacity: int = 0
	for v in slots:
		if v == null:
			capacity += max_stack
		elif v is Dictionary:
			var d: Dictionary = v as Dictionary
			if String(d.get("id", "")) == item_id:
				var c: int = int(d.get("count", 0))
				capacity += max(0, max_stack - c)
	return capacity >= count

func _get_stack_max(item_id: String) -> int:
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item_stack_max"):
		return int(db.call("get_item_stack_max", item_id))
	return 1

func _get_base_price(item_id: String) -> int:
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item"):
		var d: Dictionary = db.call("get_item", item_id) as Dictionary
		return int(d.get("vendor_price_bronze", 0))
	return 0

func _get_buy_price(item_id: String) -> int:
	var base_price: int = _get_base_price(item_id)
	return int(ceil(float(base_price) * BUY_PRICE_MULTIPLIER))

func _notify_bag_full() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_bag_full"):
		inv_ui.call("show_bag_full")

func _notify_not_enough_gold() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_center_toast"):
		inv_ui.call("show_center_toast", "Недостаточно монет")

func _is_sell_tab_active() -> bool:
	return tabs.current_tab == 1

func _is_buy_tab_active() -> bool:
	return tabs.current_tab == 0

func _is_point_over_sell_area(global_pos: Vector2) -> bool:
	if sell_scroll == null:
		return false
	var rect := sell_scroll.get_global_rect()
	return rect.has_point(global_pos)

func _get_item_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var db := get_node_or_null("/root/DataDB")
	var tex: Texture2D = null
	if db != null and db.has_method("get_item"):
		var d: Dictionary = db.call("get_item", item_id) as Dictionary
		var path: String = String(d.get("icon", ""))
		if path != "" and ResourceLoader.exists(path):
			tex = load(path)
	if tex == null:
		tex = preload("res://assets/icons/items/bag_6_common.png")
	_icon_cache[item_id] = tex
	return tex

func _show_tooltip(item_id: String, count: int, global_pos: Vector2) -> void:
	if item_id == "":
		return
	var db := get_node_or_null("/root/DataDB")
	if db != null and not db.is_ready:
		await db.initialized
	var meta: Dictionary = {}
	if db != null and db.has_method("get_item"):
		meta = db.call("get_item", item_id) as Dictionary
	var text := TOOLTIP_BUILDER.build_item_tooltip(meta, count, _player)
	if String(text).strip_edges().is_empty():
		return
	tooltip_label.text = text
	if tooltip_use_btn != null:
		tooltip_use_btn.visible = false
	if tooltip_equip_btn != null:
		tooltip_equip_btn.visible = false
	if tooltip_unequip_btn != null:
		tooltip_unequip_btn.visible = false
	await _resize_tooltip_to_content()
	tooltip_panel.visible = true
	_tooltip_item_id = item_id
	_position_tooltip_left_of_point(global_pos)

func _hide_tooltip() -> void:
	if tooltip_panel != null:
		tooltip_panel.visible = false
	_tooltip_item_id = ""

func _resize_tooltip_to_content() -> void:
	if tooltip_panel == null or tooltip_label == null:
		return
	var prev_visible := tooltip_panel.visible
	var prev_mod := tooltip_panel.modulate
	tooltip_panel.visible = true
	tooltip_panel.modulate = Color(prev_mod.r, prev_mod.g, prev_mod.b, 0.0)
	var width: float = 360.0
	tooltip_panel.size = Vector2(width, 10)
	tooltip_panel.custom_minimum_size = Vector2(width, 0)
	tooltip_label.custom_minimum_size = Vector2(width - 20.0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var label_min := tooltip_label.get_combined_minimum_size()
	if label_min.y <= 1.0:
		await get_tree().process_frame
		label_min = tooltip_label.get_combined_minimum_size()
	var content_h: float = max(float(tooltip_label.get_content_height()), label_min.y)
	var min_h: float = max(32.0, content_h + 16.0)
	tooltip_panel.custom_minimum_size = Vector2(width, min_h)
	tooltip_panel.size = Vector2(width, min_h)
	await get_tree().process_frame
	await get_tree().process_frame
	var final_size := tooltip_panel.get_combined_minimum_size()
	if final_size.y < min_h:
		final_size = Vector2(width, min_h)
	tooltip_panel.custom_minimum_size = final_size
	tooltip_panel.size = final_size
	tooltip_panel.modulate = prev_mod
	if not prev_visible:
		tooltip_panel.visible = false

func _position_tooltip_left_of_point(p: Vector2) -> void:
	if tooltip_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var size := tooltip_panel.size
	var margin: float = 8.0
	var pos := Vector2(p.x - size.x - margin, p.y)
	if pos.x < margin:
		pos.x = margin
	if pos.y + size.y > vp.y - margin:
		pos.y = p.y - size.y
	pos.y = clamp(pos.y, margin, vp.y - size.y - margin)
	tooltip_panel.position = pos

func _ensure_qty_dialog() -> void:
	if _qty_dialog != null:
		return
	_qty_dialog = Panel.new()
	_qty_dialog.name = "QtyDialog"
	_qty_dialog.visible = false
	add_child(_qty_dialog)
	_qty_dialog.size = Vector2(260, 120)
	_qty_dialog.position = Vector2(40, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.8)
	sb.border_color = Color(0.3, 0.8, 0.3)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	_qty_dialog.add_theme_stylebox_override("panel", sb)

	_qty_label = Label.new()
	_qty_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_qty_label.offset_left = 8
	_qty_label.offset_top = 6
	_qty_label.offset_right = -8
	_qty_label.offset_bottom = 28
	_qty_dialog.add_child(_qty_label)

	_qty_slider = HSlider.new()
	_qty_slider.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_qty_slider.offset_left = 8
	_qty_slider.offset_top = 32
	_qty_slider.offset_right = -8
	_qty_slider.offset_bottom = 56
	_qty_slider.value_changed.connect(_on_qty_value_changed)
	_qty_dialog.add_child(_qty_slider)

	_qty_ok = Button.new()
	_qty_ok.text = "OK"
	_qty_ok.position = Vector2(8, 66)
	_qty_ok.pressed.connect(_on_qty_ok_pressed)
	_qty_dialog.add_child(_qty_ok)

	_qty_cancel = Button.new()
	_qty_cancel.text = "Cancel"
	_qty_cancel.position = Vector2(88, 66)
	_qty_cancel.pressed.connect(_on_qty_cancel_pressed)
	_qty_dialog.add_child(_qty_cancel)

func _show_quantity_dialog(max_value: int, title_text: String) -> void:
	_qty_max = max(1, max_value)
	_qty_title = title_text
	_qty_slider.min_value = 1
	_qty_slider.max_value = _qty_max
	_qty_slider.value = int(clamp(int(_qty_max / 2.0), 1, _qty_max))
	_update_qty_label()
	_qty_dialog.visible = true

func _hide_quantity_dialog() -> void:
	if _qty_dialog != null:
		_qty_dialog.visible = false
	_qty_callback = Callable()

func _on_qty_value_changed(_v: float) -> void:
	_update_qty_label()

func _update_qty_label() -> void:
	if _qty_label == null:
		return
	var amount: int = int(_qty_slider.value)
	_qty_label.text = "%s: %d / %d" % [_qty_title, amount, _qty_max]

func _on_qty_ok_pressed() -> void:
	var amount: int = int(_qty_slider.value)
	_hide_quantity_dialog()
	if _qty_callback.is_valid():
		_qty_callback.call(amount)

func _on_qty_cancel_pressed() -> void:
	_hide_quantity_dialog()
