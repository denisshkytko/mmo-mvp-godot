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
var _group_collapsed: Dictionary = {
	"Process": false,
	"Physics": false,
	"Physics/AI details": true,
	"Engine remainder": false,
}

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
	_remember_group_collapsed_state()
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
	var process_group: TreeItem = _add_group(root, "Process", parsed.get("process_items", []), process_ms, total_ms)
	_add_metric_row(process_group, "untracked.process", untracked_process_ms, process_ms, total_ms)
	var physics_group: TreeItem = _add_group(root, "Physics", parsed.get("physics_items", []), physics_ms, total_ms)
	_add_metric_row(physics_group, "untracked.physics", untracked_physics_ms, physics_ms, total_ms)
	var ai_group: TreeItem = _add_group(physics_group, "Physics/AI details", parsed.get("ai_items", []), ai_ms, total_ms)
	ai_group.collapsed = bool(_group_collapsed.get("Physics/AI details", true))
	var engine_group: TreeItem = tree.create_item(root)
	engine_group.set_text(0, "Engine remainder")
	engine_group.set_text(1, "%.3f" % (untracked_process_ms + untracked_physics_ms))
	engine_group.set_text(2, "—")
	engine_group.set_text(3, "%.1f%%" % (((untracked_process_ms + untracked_physics_ms) / max(0.001, total_ms)) * 100.0))
	engine_group.collapsed = bool(_group_collapsed.get("Engine remainder", false))
	_add_metric_row(engine_group, "engine.untracked.process", untracked_process_ms, process_ms, total_ms)
	_add_metric_row(engine_group, "engine.untracked.physics", untracked_physics_ms, physics_ms, total_ms)


func _add_group(root: TreeItem, group_name: String, items_v: Variant, group_total_ms: float, total_ms: float) -> TreeItem:
	var group: TreeItem = tree.create_item(root)
	group.set_text(0, group_name)
	group.set_text(1, "%.3f" % group_total_ms)
	group.set_text(2, "100%")
	group.set_text(3, "%.1f%%" % ((group_total_ms / max(0.001, total_ms)) * 100.0))
	group.collapsed = bool(_group_collapsed.get(group_name, false))
	if not (items_v is Array):
		return group
	var items: Array = items_v
	for item_v in items:
		if not (item_v is Dictionary):
			continue
		var item: Dictionary = item_v
		var metric: String = String(item.get("metric", ""))
		var ms: float = float(item.get("ms", 0.0))
		_add_metric_row(group, metric, ms, group_total_ms, total_ms)
	return group


func _add_metric_row(parent: TreeItem, metric: String, ms: float, group_total_ms: float, total_ms: float) -> void:
	var row: TreeItem = tree.create_item(parent)
	row.set_text(0, metric)
	row.set_text(1, "%.3f" % ms)
	row.set_text(2, "%.1f%%" % ((ms / max(0.001, group_total_ms)) * 100.0))
	row.set_text(3, "%.1f%%" % ((ms / max(0.001, total_ms)) * 100.0))


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


func _remember_group_collapsed_state() -> void:
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	var child: TreeItem = root.get_first_child()
	while child != null:
		var name: String = child.get_text(0)
		_group_collapsed[name] = child.collapsed
		var subchild: TreeItem = child.get_first_child()
		while subchild != null:
			_group_collapsed["%s/%s" % [name, subchild.get_text(0)]] = subchild.collapsed
			subchild = subchild.get_next()
		child = child.get_next()
