extends Control
class_name PerformanceProfilerWindow

signal closed

@onready var root_panel: Panel = $Margin/Panel
@onready var close_button: Button = $Margin/Panel/VBox/Header/CloseButton
@onready var copy_button: Button = $Margin/Panel/VBox/Header/CopyButton
@onready var summary_label: RichTextLabel = $Margin/Panel/VBox/Summary
@onready var tree: Tree = $Margin/Panel/VBox/MetricsTree

var _refresh_timer: float = 0.0
const REFRESH_SEC: float = 0.5
var _collapsed_paths: Dictionary = {}

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	tree.columns = 4
	tree.set_column_title(0, "Metric")
	tree.set_column_title(1, "ms/f")
	tree.set_column_title(2, "Group %")
	tree.set_column_title(3, "Total %")
	tree.set_column_titles_visible(true)
	_refresh_from_runtime_overlay()


func _process(delta: float) -> void:
	_refresh_timer += max(0.0, delta)
	if _refresh_timer < REFRESH_SEC:
		return
	_refresh_timer = 0.0
	_refresh_from_runtime_overlay()


func _on_close_pressed() -> void:
	hide()
	emit_signal("closed")


func _on_copy_pressed() -> void:
	var label: Label = _find_runtime_label()
	if label == null:
		DisplayServer.clipboard_set("[Runtime Profiler]\nno data")
		return
	DisplayServer.clipboard_set(label.text)


func _refresh_from_runtime_overlay() -> void:
	var label: Label = _find_runtime_label()
	if label == null:
		summary_label.text = "[b]Runtime profiler data is not available yet[/b]"
		_build_tree({}, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		return
	var parsed: Dictionary = _parse_runtime_text(label.text)
	_capture_collapsed_state()
	var process_ms: float = float(parsed.get("process_ms", 0.0))
	var physics_ms: float = float(parsed.get("physics_ms", 0.0))
	var tracked_process_ms: float = float(parsed.get("tracked_process_ms", 0.0))
	var tracked_physics_ms: float = float(parsed.get("tracked_physics_ms", 0.0))
	var tracked_ai_ms: float = float(parsed.get("tracked_ai_ms", 0.0))
	var untracked_process_ms: float = float(parsed.get("untracked_process_ms", max(0.0, process_ms - tracked_process_ms)))
	var untracked_physics_ms: float = float(parsed.get("untracked_physics_ms", max(0.0, physics_ms - tracked_physics_ms)))
	var total_ms: float = max(0.001, process_ms + physics_ms)
	summary_label.text = (
		"[b]Runtime summary[/b]\n"
		+ "process=%.2fms (tracked %.2fms, %.1f%%)\n" % [process_ms, tracked_process_ms, (tracked_process_ms / max(0.001, process_ms)) * 100.0]
		+ "physics=%.2fms (tracked %.2fms, %.1f%%)\n" % [physics_ms, tracked_physics_ms, (tracked_physics_ms / max(0.001, physics_ms)) * 100.0]
		+ "ai=%.2fms (included inside physics: %.1f%%)\n" % [tracked_ai_ms, (tracked_ai_ms / max(0.001, physics_ms)) * 100.0]
		+ "untracked process=%.2fms, untracked physics=%.2fms\n" % [untracked_process_ms, untracked_physics_ms]
		+ "combined tracked influence=%.1f%%" % [((tracked_process_ms + tracked_physics_ms) / total_ms) * 100.0]
	)
	_build_tree(parsed, process_ms, physics_ms, tracked_ai_ms, total_ms, untracked_process_ms, untracked_physics_ms)


func _build_tree(
	parsed: Dictionary,
	process_ms: float,
	physics_ms: float,
	ai_ms: float,
	total_ms: float,
	untracked_process_ms: float,
	untracked_physics_ms: float
) -> void:
	tree.clear()
	var root: TreeItem = tree.create_item()
	var process_group: TreeItem = _add_group(root, "Process", process_ms, total_ms, "")
	for item_v in _as_metric_items(parsed.get("process_items", [])):
		_add_metric_row(process_group, String(item_v.get("metric", "")), float(item_v.get("ms", 0.0)), process_ms, total_ms, "Process")
	_add_metric_row(process_group, "untracked.process", untracked_process_ms, process_ms, total_ms, "Process")
	var physics_group: TreeItem = _add_group(root, "Physics", physics_ms, total_ms, "")
	_build_physics_hierarchy(
		physics_group,
		_as_metric_items(parsed.get("physics_items", [])),
		_as_metric_items(parsed.get("ai_items", [])),
		physics_ms,
		total_ms
	)
	_add_metric_row(physics_group, "untracked.physics", untracked_physics_ms, physics_ms, total_ms, "Physics")
	var engine_group: TreeItem = tree.create_item(root)
	engine_group.set_text(0, "Engine remainder")
	engine_group.set_text(1, "%.3f" % (untracked_process_ms + untracked_physics_ms))
	engine_group.set_text(2, "—")
	engine_group.set_text(3, "%.1f%%" % (((untracked_process_ms + untracked_physics_ms) / max(0.001, total_ms)) * 100.0))
	_apply_collapsed_state(engine_group, "Engine remainder")
	_add_metric_row(engine_group, "engine.untracked.process", untracked_process_ms, process_ms, total_ms, "Engine remainder")
	_add_metric_row(engine_group, "engine.untracked.physics", untracked_physics_ms, physics_ms, total_ms, "Engine remainder")


func _add_group(root: TreeItem, group_name: String, group_total_ms: float, total_ms: float, parent_path: String) -> TreeItem:
	var group: TreeItem = tree.create_item(root)
	group.set_text(0, group_name)
	group.set_text(1, "%.3f" % group_total_ms)
	group.set_text(2, "100%")
	group.set_text(3, "%.1f%%" % ((group_total_ms / max(0.001, total_ms)) * 100.0))
	var path := group_name if parent_path == "" else "%s/%s" % [parent_path, group_name]
	_apply_collapsed_state(group, path)
	return group


func _add_metric_row(parent: TreeItem, metric: String, ms: float, group_total_ms: float, total_ms: float, parent_path: String) -> TreeItem:
	var row: TreeItem = tree.create_item(parent)
	row.set_text(0, metric)
	row.set_text(1, "%.3f" % ms)
	row.set_text(2, "%.1f%%" % ((ms / max(0.001, group_total_ms)) * 100.0))
	row.set_text(3, "%.1f%%" % ((ms / max(0.001, total_ms)) * 100.0))
	var path := metric if parent_path == "" else "%s/%s" % [parent_path, metric]
	_apply_collapsed_state(row, path)
	return row


func _build_physics_hierarchy(
	physics_group: TreeItem,
	physics_items: Array[Dictionary],
	ai_items: Array[Dictionary],
	physics_ms: float,
	total_ms: float
) -> void:
	var parent_rows: Dictionary = {}
	for item in physics_items:
		var metric: String = String(item.get("metric", ""))
		var ms: float = float(item.get("ms", 0.0))
		if metric.ends_with(".total"):
			var row: TreeItem = _add_metric_row(physics_group, metric, ms, physics_ms, total_ms, "Physics")
			parent_rows[_physics_parent_key(metric)] = row
	for item in physics_items:
		var metric: String = String(item.get("metric", ""))
		if metric.ends_with(".total"):
			continue
		var ms: float = float(item.get("ms", 0.0))
		var parent_key: String = _physics_parent_key(metric)
		if parent_rows.has(parent_key):
			_add_metric_row(parent_rows[parent_key], metric, ms, physics_ms, total_ms, "Physics/%s" % parent_key)
		else:
			_add_metric_row(physics_group, metric, ms, physics_ms, total_ms, "Physics")
	for item in ai_items:
		var metric: String = String(item.get("metric", ""))
		var ms: float = float(item.get("ms", 0.0))
		var parent_key: String = _physics_parent_key(metric)
		if parent_rows.has(parent_key):
			_add_metric_row(parent_rows[parent_key], metric, ms, physics_ms, total_ms, "Physics/%s" % parent_key)
		else:
			_add_metric_row(physics_group, metric, ms, physics_ms, total_ms, "Physics")


func _find_runtime_label() -> Label:
	return get_tree().get_root().find_child("__runtime_profiler_label", true, false) as Label


func _parse_runtime_text(text: String) -> Dictionary:
	var result: Dictionary = {
		"process_ms": 0.0,
		"physics_ms": 0.0,
			"tracked_process_ms": 0.0,
			"tracked_physics_ms": 0.0,
			"tracked_ai_ms": 0.0,
			"untracked_process_ms": 0.0,
			"untracked_physics_ms": 0.0,
			"process_items": [],
			"physics_items": [],
			"ai_items": [],
	}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("process="):
			result["process_ms"] = _extract_float_after(line, "process=")
			result["physics_ms"] = _extract_float_after(line, "physics=")
		elif line.begins_with("tracked proc="):
			result["tracked_process_ms"] = _extract_float_after(line, "tracked proc=")
			result["untracked_process_ms"] = _extract_float_after(line, "untracked~")
		elif line.begins_with("tracked phys="):
			result["tracked_physics_ms"] = _extract_float_after(line, "tracked phys=")
			result["untracked_physics_ms"] = _extract_float_after(line, "untracked~")
		elif line.begins_with("tracked ai="):
			result["tracked_ai_ms"] = _extract_float_after(line, "tracked ai=")
		elif line.begins_with("script.process "):
			result["process_items"] = _parse_metric_items(line.trim_prefix("script.process "))
		elif line.begins_with("script.physics "):
			result["physics_items"] = _parse_metric_items(line.trim_prefix("script.physics "))
		elif line.begins_with("script.ai "):
			result["ai_items"] = _parse_metric_items(line.trim_prefix("script.ai "))
	return result


func _parse_metric_items(payload: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for part in payload.split(", "):
		var eq_idx := part.find("=")
		if eq_idx <= 0:
			continue
		var metric := part.substr(0, eq_idx)
		var value_part := part.substr(eq_idx + 1)
		var ms := _extract_float_before(value_part, "ms/f")
		items.append({"metric": metric, "ms": ms})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("ms", 0.0)) > float(b.get("ms", 0.0))
	)
	return items


func _extract_float_after(text: String, token: String) -> float:
	var idx := text.find(token)
	if idx < 0:
		return 0.0
	var tail := text.substr(idx + token.length())
	return _extract_float_before(tail, "ms")


func _extract_float_before(text: String, token: String) -> float:
	var idx := text.find(token)
	var number_str := text if idx < 0 else text.substr(0, idx)
	number_str = number_str.strip_edges()
	return float(number_str) if number_str.is_valid_float() else 0.0


func _capture_collapsed_state() -> void:
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	_collapsed_paths.clear()
	_capture_item_state_recursive(root, "")


func _capture_item_state_recursive(item: TreeItem, parent_path: String) -> void:
	var child: TreeItem = item.get_first_child()
	while child != null:
		var name := child.get_text(0)
		var path := name if parent_path == "" else "%s/%s" % [parent_path, name]
		_collapsed_paths[path] = child.collapsed
		_capture_item_state_recursive(child, path)
		child = child.get_next()


func _apply_collapsed_state(item: TreeItem, path: String) -> void:
	if _collapsed_paths.has(path):
		item.collapsed = bool(_collapsed_paths.get(path, false))
	else:
		item.collapsed = false


func _as_metric_items(items_v: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (items_v is Array):
		return result
	for item_v in items_v:
		if item_v is Dictionary:
			result.append(item_v as Dictionary)
	return result


func _physics_parent_key(metric: String) -> String:
	if metric.ends_with(".total"):
		return metric.trim_suffix(".total")
	if metric.find(".ai.") != -1:
		return metric.split(".ai.")[0]
	if metric.find(".ai_") != -1:
		return metric.split(".ai_")[0]
	return metric.get_slice(".", 0)
