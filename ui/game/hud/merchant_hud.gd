extends CanvasLayer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")

const BUY_PRICE_MULTIPLIER: float = 1.25
const TOOLTIP_HOLD_MAX_MS: int = 1000

@onready var panel: Panel = $Root/Panel
@onready var title_label: Label = $Root/Panel/Title
@onready var close_button: Button = $Root/Panel/CloseButton
@onready var item_cell_template: Panel = $Root/Panel/ItemCellTemplate
@onready var tabs: TabContainer = $Root/Panel/Tabs
@onready var buy_scroll: ScrollContainer = $Root/Panel/Tabs/Покупка/Scroll
@onready var sell_scroll: ScrollContainer = $Root/Panel/Tabs/Продажа/Scroll
@onready var buy_grid: GridContainer = $Root/Panel/Tabs/Покупка/Scroll/Margin/Grid
@onready var sell_grid: GridContainer = $Root/Panel/Tabs/Продажа/Scroll/Margin/Grid

@onready var tooltip_panel: Panel = $Root/TooltipPanel
@onready var tooltip_label: RichTextLabel = $Root/TooltipPanel/Margin/VBox/Text
@onready var tooltip_use_btn: Button = $Root/TooltipPanel/Margin/VBox/UseButton
@onready var tooltip_equip_btn: Button = $Root/TooltipPanel/Margin/VBox/EquipButton
@onready var tooltip_unequip_btn: Button = $Root/TooltipPanel/Margin/VBox/UnequipButton
@onready var tooltip_close_button: Button = $Root/TooltipPanel/CloseButton

@onready var qty_dialog: Panel = $Root/QtyDialog
@onready var qty_title: Label = $Root/QtyDialog/QtyTitle
@onready var qty_slider: HSlider = $Root/QtyDialog/QtySlider
@onready var qty_price: Label = $Root/QtyDialog/QtyPrice
@onready var qty_ok: Button = $Root/QtyDialog/QtyOk
@onready var qty_cancel: Button = $Root/QtyDialog/QtyCancel

var _player: Node = null
var _merchant: Node = null
var _is_open: bool = false

var _buy_entries: Array[Dictionary] = []
var _sell_entries: Array[Dictionary] = []

var _icon_cache: Dictionary = {}
var _tooltip_item_id: String = ""
var _names_pending: bool = false
var _tooltip_layer: CanvasLayer = null
var _dialog_layer: CanvasLayer = null

# Quantity dialog
var _qty_callback: Callable = Callable()
var _qty_max: int = 1
var _qty_title: String = ""
var _qty_item_id: String = ""
var _qty_is_buy: bool = false
var _qty_slot_index: int = -1

# Sell refresh
var _sell_refresh_accum: float = 0.0

var _tooltip_press_ms: int = 0
var _tooltip_press_item_id: String = ""
var _tooltip_press_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	panel.visible = false
	tooltip_panel.visible = false
	_ensure_tooltip_layer()
	if tooltip_panel != null:
		tooltip_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 1.0)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		tooltip_panel.add_theme_stylebox_override("panel", sb)
	if tooltip_label != null:
		tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tooltip_close_button != null:
		tooltip_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if close_button != null and not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	if tooltip_use_btn != null:
		tooltip_use_btn.visible = false
	if tooltip_equip_btn != null:
		tooltip_equip_btn.visible = false
	if tooltip_unequip_btn != null:
		tooltip_unequip_btn.visible = false
	if tooltip_close_button != null and not tooltip_close_button.pressed.is_connected(_hide_tooltip):
		tooltip_close_button.pressed.connect(_hide_tooltip)
	_setup_qty_dialog()

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
	_sync_inventory_trade_state(false)
	_merchant = null

func _process(delta: float) -> void:
	if not _is_open:
		return
	if _merchant != null and not is_instance_valid(_merchant):
		close()
		return
	_sell_refresh_accum += delta
	if _sell_refresh_accum >= 1.0:
		_sell_refresh_accum = 0.0
		_refresh_sell_grid()
	if _names_pending:
		var db := get_node_or_null("/root/DataDB")
		if db != null and db.is_ready:
			_names_pending = false
			_refresh_buy_grid()
			_refresh_sell_grid()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if tooltip_panel != null and tooltip_panel.visible:
		if event is InputEventMouseButton:
			var mb2 := event as InputEventMouseButton
			if mb2.button_index == MOUSE_BUTTON_LEFT and mb2.pressed:
				if tooltip_close_button != null and tooltip_close_button.get_global_rect().has_point(mb2.global_position):
					_hide_tooltip()
					return
				_hide_tooltip()
		elif event is InputEventScreenTouch:
			if (event as InputEventScreenTouch).pressed:
				if tooltip_close_button != null and tooltip_close_button.get_global_rect().has_point((event as InputEventScreenTouch).position):
					_hide_tooltip()
					return
				_hide_tooltip()

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
			if v is MerchantItemEntry:
				var entry := v as MerchantItemEntry
				var item_id: String = entry.item_id
				var count: int = entry.count
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
		var cell := _build_item_cell(item_id, count, "Купить", true, -1)
		buy_grid.add_child(cell)
	var db := get_node_or_null("/root/DataDB")
	if db != null and not db.is_ready:
		_names_pending = true

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
	if item_cell_template == null:
		return Panel.new()
	var cell: Panel = item_cell_template.duplicate(0) as Panel
	cell.visible = true
	var base_size := item_cell_template.get_combined_minimum_size()
	if base_size.y > 0.0:
		cell.custom_minimum_size = Vector2(base_size.x, base_size.y + 10.0)

	var icon_panel: Panel = cell.get_node_or_null("Padding/Content/IconPanel") as Panel
	var icon: TextureRect = cell.get_node_or_null("Padding/Content/IconPanel/Icon") as TextureRect
	var name_label: Label = cell.get_node_or_null("Padding/Content/Name") as Label
	var action_button: Button = cell.get_node_or_null("Padding/Content/ActionButton") as Button
	var action_label: RichTextLabel = cell.get_node_or_null("Padding/Content/ActionButton/ActionText") as RichTextLabel

	if icon != null:
		icon.texture = _get_item_icon(item_id)
	if name_label != null:
		name_label.text = _format_item_label(item_id, count)
	if action_label != null:
		action_label.bbcode_enabled = true
		action_label.text = _format_action_bbcode(action_text, item_id, count, is_buy)
	if action_button != null and action_label == null:
		action_button.text = _format_action_text(action_text, item_id, count, is_buy)

	if icon_panel != null:
		icon_panel.gui_input.connect(_on_item_tooltip_input.bind(item_id, count))
	if name_label != null:
		name_label.gui_input.connect(_on_item_tooltip_input.bind(item_id, count))

	if action_button != null:
		if is_buy:
			action_button.pressed.connect(_on_buy_button_pressed.bind(item_id, count))
		else:
			action_button.pressed.connect(_on_buyback_button_pressed.bind(item_id, count, sale_id))

	return cell

func _format_action_text(action_text: String, item_id: String, count: int, is_buy: bool) -> String:
	var price_per: int = _get_buy_price(item_id) if is_buy else _get_base_price(item_id)
	var total: int = price_per if is_buy else price_per * max(1, count)
	return "%s\n%s" % [action_text, _format_money_short(total)]

func _format_action_bbcode(action_text: String, item_id: String, count: int, is_buy: bool) -> String:
	var price_per: int = _get_buy_price(item_id) if is_buy else _get_base_price(item_id)
	var total: int = price_per if is_buy else price_per * max(1, count)
	return "%s\n%s" % [action_text, TOOLTIP_BUILDER.format_money_bbcode(total)]

func _format_money_short(bronze_total: int) -> String:
	var total: int = max(0, int(bronze_total))
	var gold: int = int(total / 10000)
	var silver: int = int((total % 10000) / 100)
	var bronze: int = int(total % 100)
	var parts: Array[String] = []
	if gold > 0:
		parts.append("%dg" % gold)
	if silver > 0 or gold > 0:
		parts.append("%ds" % silver)
	parts.append("%db" % bronze)
	return " ".join(parts)

func _ensure_tooltip_layer() -> void:
	if tooltip_panel == null:
		return
	if _tooltip_layer == null:
		_tooltip_layer = CanvasLayer.new()
		_tooltip_layer.name = "TooltipLayer"
		_tooltip_layer.layer = 200
		add_child(_tooltip_layer)
	if tooltip_panel.get_parent() != _tooltip_layer:
		tooltip_panel.reparent(_tooltip_layer)

func _ensure_dialog_layer() -> void:
	if _dialog_layer == null:
		_dialog_layer = CanvasLayer.new()
		_dialog_layer.name = "DialogLayer"
		_dialog_layer.layer = 210
		add_child(_dialog_layer)

func _format_item_label(item_id: String, count: int) -> String:
	var db := get_node_or_null("/root/DataDB")
	var name: String = item_id
	if db != null and db.is_ready and db.has_method("get_item_name"):
		name = String(db.call("get_item_name", item_id))
	if count > 1:
		return "%s x%d" % [name, count]
	return name

func _on_item_tooltip_input(event: InputEvent, item_id: String, count: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_tooltip_press_ms = Time.get_ticks_msec()
			_tooltip_press_item_id = item_id
			_tooltip_press_pos = mb.global_position
			return
		if _tooltip_press_item_id != item_id:
			return
		if mb.global_position.distance_to(_tooltip_press_pos) > 1.0:
			_tooltip_press_item_id = ""
			return
		var held_ms := Time.get_ticks_msec() - _tooltip_press_ms
		_tooltip_press_item_id = ""
		if held_ms > TOOLTIP_HOLD_MAX_MS:
			return
		_toggle_tooltip(item_id, count, mb.global_position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_tooltip_press_ms = Time.get_ticks_msec()
			_tooltip_press_item_id = item_id
			_tooltip_press_pos = st.position
			return
		if _tooltip_press_item_id != item_id:
			return
		if st.position.distance_to(_tooltip_press_pos) > 1.0:
			_tooltip_press_item_id = ""
			return
		var held_ms := Time.get_ticks_msec() - _tooltip_press_ms
		_tooltip_press_item_id = ""
		if held_ms > TOOLTIP_HOLD_MAX_MS:
			return
		_toggle_tooltip(item_id, count, st.position)

func _toggle_tooltip(item_id: String, count: int, global_pos: Vector2) -> void:
	if tooltip_panel != null and tooltip_panel.visible and _tooltip_item_id == item_id:
		_hide_tooltip()
		return
	_show_tooltip(item_id, count, global_pos)

func _on_buy_button_pressed(item_id: String, count: int) -> void:
	var stack_max := _get_stack_max(item_id)
	if stack_max <= 1:
		_try_buy_item(item_id, 1)
		return
	_show_quantity_dialog(stack_max, "Купить", item_id, true)
	_qty_callback = Callable(self, "_on_buy_quantity_selected").bind(item_id)

func _on_buy_quantity_selected(amount: int, item_id: String) -> void:
	_try_buy_item(item_id, amount)

func request_sell_from_inventory(item_id: String, max_count: int) -> void:
	if max_count <= 1:
		sell_items_from_inventory(item_id, 1)
		return
	_show_quantity_dialog(max_count, "Продать", item_id, false)
	_qty_callback = Callable(self, "_on_sell_quantity_selected").bind(item_id)

func request_sell_from_inventory_slot(item_id: String, max_count: int, slot_index: int) -> void:
	_qty_slot_index = slot_index
	if max_count <= 1:
		sell_items_from_inventory_slot(item_id, 1, slot_index)
		return
	_show_quantity_dialog(max_count, "Продать", item_id, false)
	_qty_callback = Callable(self, "_on_sell_slot_quantity_selected").bind(item_id, slot_index)

func _on_sell_quantity_selected(amount: int, item_id: String) -> void:
	sell_items_from_inventory(item_id, amount)

func _on_sell_slot_quantity_selected(amount: int, item_id: String, slot_index: int) -> void:
	sell_items_from_inventory_slot(item_id, amount, slot_index)

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

func sell_items_from_inventory_slot(item_id: String, count: int, slot_index: int) -> void:
	if _player == null or _merchant == null:
		return
	if count <= 0:
		return
	if not _player.has_method("get_inventory_snapshot") or not _player.has_method("apply_inventory_snapshot"):
		return
	var snap: Dictionary = _player.call("get_inventory_snapshot") as Dictionary
	var slots: Array = snap.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return
	var v: Variant = slots[slot_index]
	if v == null or not (v is Dictionary):
		return
	var d: Dictionary = v as Dictionary
	if String(d.get("id", "")) != item_id:
		return
	var current: int = int(d.get("count", 0))
	if current <= 0:
		return
	var removed: int = min(count, current)
	if removed <= 0:
		return
	if removed >= current:
		slots[slot_index] = null
	else:
		d["count"] = current - removed
		slots[slot_index] = d
	snap["slots"] = slots
	_player.call("apply_inventory_snapshot", snap)
	var gold_gain: int = _get_base_price(item_id) * removed
	_player.call("add_gold", gold_gain)
	if _merchant.has_method("add_merchant_sale"):
		_merchant.call("add_merchant_sale", _player.get_instance_id(), item_id, removed)
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

func _setup_qty_dialog() -> void:
	if qty_dialog == null:
		return
	qty_dialog.visible = false
	_ensure_dialog_layer()
	if qty_dialog.get_parent() != _dialog_layer:
		qty_dialog.reparent(_dialog_layer)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.8)
	sb.border_color = Color(0.3, 0.8, 0.3)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	qty_dialog.add_theme_stylebox_override("panel", sb)
	if qty_slider != null and not qty_slider.value_changed.is_connected(_on_qty_value_changed):
		qty_slider.value_changed.connect(_on_qty_value_changed)
	if qty_ok != null and not qty_ok.pressed.is_connected(_on_qty_ok_pressed):
		qty_ok.pressed.connect(_on_qty_ok_pressed)
	if qty_cancel != null and not qty_cancel.pressed.is_connected(_on_qty_cancel_pressed):
		qty_cancel.pressed.connect(_on_qty_cancel_pressed)

func _show_quantity_dialog(max_value: int, title_text: String, item_id: String, is_buy: bool) -> void:
	_qty_max = max(1, max_value)
	_qty_title = title_text
	_qty_item_id = item_id
	_qty_is_buy = is_buy
	if qty_slider != null:
		qty_slider.min_value = 1
		qty_slider.max_value = _qty_max
		qty_slider.value = int(clamp(int(_qty_max / 2.0), 1, _qty_max))
	_update_qty_label()
	if qty_dialog != null:
		qty_dialog.visible = true

func _hide_quantity_dialog() -> void:
	if qty_dialog != null:
		qty_dialog.visible = false
	if qty_slider != null:
		qty_slider.value = qty_slider.min_value
	_qty_callback = Callable()
	_qty_item_id = ""
	_qty_is_buy = false
	_qty_slot_index = -1

func _on_qty_value_changed(_v: float) -> void:
	_update_qty_label()

func _update_qty_label() -> void:
	var amount: int = int(qty_slider.value) if qty_slider != null else 1
	if qty_title != null:
		qty_title.text = "%s: %d / %d" % [_qty_title, amount, _qty_max]
	if qty_price != null:
		var price_per := _get_buy_price(_qty_item_id) if _qty_is_buy else _get_base_price(_qty_item_id)
		var total := price_per * amount
		qty_price.text = "Цена: %s" % _format_money_short(total)

func _on_qty_ok_pressed() -> void:
	var amount: int = int(qty_slider.value) if qty_slider != null else 1
	var cb := _qty_callback
	_hide_quantity_dialog()
	if cb.is_valid():
		cb.call(amount)

func _on_qty_cancel_pressed() -> void:
	_hide_quantity_dialog()
