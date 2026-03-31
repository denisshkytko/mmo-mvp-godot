extends Control
class_name PerformanceProfilerWindow

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
signal closed

@onready var close_button: Button = $Margin/Panel/VBox/Header/CloseButton
@onready var copy_button: Button = $Margin/Panel/VBox/Header/CopyButton
@onready var summary_label: RichTextLabel = $Margin/Panel/VBox/Summary
@onready var tree: Tree = $Margin/Panel/VBox/MetricsTree

const REFRESH_SEC: float = 0.5
var _refresh_timer: float = 0.0
var _collapsed_paths: Dictionary = {}

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	copy_button.add_theme_font_size_override("font_size", 22)
	close_button.add_theme_font_size_override("font_size", 22)
	summary_label.add_theme_font_size_override("normal_font_size", 22)
	tree.add_theme_font_size_override("font_size", 22)
	tree.columns = 4
	tree.set_column_title(0, "Metric")
	tree.set_column_title(1, "ms/f")
	tree.set_column_title(2, "Group %")
	tree.set_column_title(3, "Total %")
	tree.set_column_titles_visible(true)
	_refresh_from_runtime_overlay()


func _process(delta: float) -> void:
	var t_total := Time.get_ticks_usec()
	_refresh_timer += max(0.0, delta)
	if _refresh_timer < REFRESH_SEC:
		FRAME_PROFILER.add_usec("process.hud.performance_profiler_window.total", Time.get_ticks_usec() - t_total)
		return
	_refresh_timer = 0.0
	_refresh_from_runtime_overlay()
	FRAME_PROFILER.add_usec("process.hud.performance_profiler_window.total", Time.get_ticks_usec() - t_total)


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
		_build_tree({}, 0.0, 0.0, 0.0, 0.0, 0.0)
		return

	_capture_collapsed_state()
	var parsed: Dictionary = _parse_runtime_text(label.text)
	var process_ms: float = float(parsed.get("process_ms", 0.0))
	var physics_ms: float = float(parsed.get("physics_ms", 0.0))
	var tracked_process_ms: float = float(parsed.get("tracked_process_ms", 0.0))
	var tracked_physics_ms: float = float(parsed.get("tracked_physics_ms", 0.0))
	var untracked_process_ms: float = float(parsed.get("untracked_process_ms", max(0.0, process_ms - tracked_process_ms)))
	var untracked_physics_ms: float = float(parsed.get("untracked_physics_ms", max(0.0, physics_ms - tracked_physics_ms)))
	var fps: int = int(parsed.get("fps", 0))
	var frames: int = int(parsed.get("frames", 0))
	var phys_frames: int = int(parsed.get("phys_frames", 0))
	var draws: int = int(parsed.get("draws", 0))
	var scene_nodes: int = int(parsed.get("scene_nodes", 0))

	summary_label.text = (
		"[b]Runtime summary[/b]\n"
		+ "fps=%d frames=%d phys_frames=%d draws=%d nodes=%d\n" % [fps, frames, phys_frames, draws, scene_nodes]
		+ "process=%.2fms (tracked %.2fms, %.1f%%)\n" % [process_ms, tracked_process_ms, (tracked_process_ms / max(0.001, process_ms)) * 100.0]
		+ "physics=%.2fms (tracked %.2fms, %.1f%%)\n" % [physics_ms, tracked_physics_ms, (tracked_physics_ms / max(0.001, physics_ms)) * 100.0]
		+ "untracked process=%.2fms, untracked physics=%.2fms\n" % [untracked_process_ms, untracked_physics_ms]
		+ "(process coverage uses TIME_PROCESS: engine + scripts)"
	)

	_build_tree(parsed, process_ms, physics_ms, process_ms + physics_ms, untracked_process_ms, untracked_physics_ms)


func _build_tree(parsed: Dictionary, process_ms: float, physics_ms: float, total_ms: float, untracked_process_ms: float, untracked_physics_ms: float) -> void:
	tree.clear()
	var root := tree.create_item()

	var process_group := _add_group(root, "Process", process_ms, total_ms, "")
	_build_process_hierarchy(process_group, _as_metric_items(parsed.get("process_items", [])), process_ms, total_ms)
	_add_metric_row(process_group, "untracked.process", untracked_process_ms, process_ms, total_ms, "Process")

	var physics_group := _add_group(root, "Physics", physics_ms, total_ms, "")
	_build_physics_hierarchy(
		physics_group,
		_as_metric_items(parsed.get("physics_items", [])),
		_as_metric_items(parsed.get("ai_items", [])),
		_as_metric_items(parsed.get("combat_items", [])),
		physics_ms,
		total_ms
	)
	_add_metric_row(physics_group, "untracked.physics", untracked_physics_ms, physics_ms, total_ms, "Physics")

	var engine_items := _as_metric_items(parsed.get("engine_process_items", []))
	var engine_total_ms: float = 0.0
	for item in engine_items:
		engine_total_ms += float(item.get("ms", 0.0))
	var engine_group := _add_group(root, "Engine process monitors", engine_total_ms, total_ms, "")
	for item in engine_items:
		_add_metric_row(
			engine_group,
			String(item.get("metric", "")),
			float(item.get("ms", 0.0)),
			max(0.001, engine_total_ms),
			total_ms,
			"Engine process monitors"
		)
	var count_items := _as_metric_items(parsed.get("count_items", []))
	var count_group := _add_group(root, "Event counters", 0.0, max(0.001, total_ms), "")
	for item in count_items:
		var row := tree.create_item(count_group)
		row.set_text(0, String(item.get("metric", "")))
		row.set_text(1, "%.2f/f" % float(item.get("count_per_frame", 0.0)))
		row.set_text(2, "n/a")
		row.set_text(3, "n/a")


func _add_group(parent: TreeItem, name: String, group_ms: float, total_ms: float, parent_path: String) -> TreeItem:
	var item := tree.create_item(parent)
	item.set_text(0, name)
	item.set_text(1, "%.3f" % group_ms)
	item.set_text(2, "100%")
	item.set_text(3, "%.1f%%" % ((group_ms / max(0.001, total_ms)) * 100.0))
	var path := name if parent_path == "" else "%s/%s" % [parent_path, name]
	_apply_collapsed_state(item, path)
	return item


func _add_metric_row(parent: TreeItem, metric: String, ms: float, group_ms: float, total_ms: float, parent_path: String) -> TreeItem:
	var row := tree.create_item(parent)
	row.set_text(0, metric)
	row.set_text(1, "%.3f" % ms)
	row.set_text(2, "%.1f%%" % ((ms / max(0.001, group_ms)) * 100.0))
	row.set_text(3, "%.1f%%" % ((ms / max(0.001, total_ms)) * 100.0))
	var path := metric if parent_path == "" else "%s/%s" % [parent_path, metric]
	_apply_collapsed_state(row, path)
	return row


func _build_process_hierarchy(process_group: TreeItem, process_items: Array[Dictionary], process_ms: float, total_ms: float) -> void:
	var parent_rows: Dictionary = {}
	var parent_totals_ms: Dictionary = {}
	for item in process_items:
		var metric := String(item.get("metric", ""))
		if metric.ends_with(".total"):
			var metric_ms := float(item.get("ms", 0.0))
			var parent_key := _process_parent_key(metric)
			var row := _add_metric_row(process_group, metric, metric_ms, process_ms, total_ms, "Process")
			parent_rows[parent_key] = row
			parent_totals_ms[parent_key] = metric_ms
	for item in process_items:
		var metric := String(item.get("metric", ""))
		if metric.ends_with(".total"):
			continue
		var parent_key := _process_parent_key(metric)
		if parent_rows.has(parent_key):
			var parent_ms: float = max(0.001, float(parent_totals_ms.get(parent_key, process_ms)))
			_add_metric_row(parent_rows[parent_key], metric, float(item.get("ms", 0.0)), parent_ms, total_ms, "Process/%s" % parent_key)
		else:
			_add_metric_row(process_group, metric, float(item.get("ms", 0.0)), process_ms, total_ms, "Process")


func _build_physics_hierarchy(
	physics_group: TreeItem,
	physics_items: Array[Dictionary],
	ai_items: Array[Dictionary],
	combat_items: Array[Dictionary],
	physics_ms: float,
	total_ms: float
) -> void:
	var parent_rows: Dictionary = {}
	var parent_totals_ms: Dictionary = {}
	for item in physics_items:
		var metric := String(item.get("metric", ""))
		if metric.ends_with(".total"):
			var metric_ms := float(item.get("ms", 0.0))
			var parent_key := _physics_parent_key(metric)
			var row := _add_metric_row(physics_group, metric, metric_ms, physics_ms, total_ms, "Physics")
			parent_rows[parent_key] = row
			parent_totals_ms[parent_key] = metric_ms
	for item in physics_items:
		var metric := String(item.get("metric", ""))
		if metric.ends_with(".total"):
			continue
		var parent_key := _physics_parent_key(metric)
		if parent_rows.has(parent_key):
			var parent_ms: float = max(0.001, float(parent_totals_ms.get(parent_key, physics_ms)))
			_add_metric_row(parent_rows[parent_key], metric, float(item.get("ms", 0.0)), parent_ms, total_ms, "Physics/%s" % parent_key)
		else:
			_add_metric_row(physics_group, metric, float(item.get("ms", 0.0)), physics_ms, total_ms, "Physics")
	for item in ai_items:
		var metric := String(item.get("metric", ""))
		var parent_key := _physics_parent_key(metric)
		if parent_rows.has(parent_key):
			var parent_ms: float = max(0.001, float(parent_totals_ms.get(parent_key, physics_ms)))
			_add_metric_row(parent_rows[parent_key], metric, float(item.get("ms", 0.0)), parent_ms, total_ms, "Physics/%s" % parent_key)
		else:
			_add_metric_row(physics_group, metric, float(item.get("ms", 0.0)), physics_ms, total_ms, "Physics")
	for item in combat_items:
		var metric := String(item.get("metric", ""))
		var parent_key := _physics_parent_key(metric)
		if parent_rows.has(parent_key):
			var parent_ms: float = max(0.001, float(parent_totals_ms.get(parent_key, physics_ms)))
			_add_metric_row(parent_rows[parent_key], metric, float(item.get("ms", 0.0)), parent_ms, total_ms, "Physics/%s" % parent_key)
		else:
			_add_metric_row(physics_group, metric, float(item.get("ms", 0.0)), physics_ms, total_ms, "Physics")


func _find_runtime_label() -> Label:
	return get_tree().get_root().find_child("__runtime_profiler_label", true, false) as Label


func _parse_runtime_text(text: String) -> Dictionary:
	var result: Dictionary = {
		"process_ms": 0.0,
		"physics_ms": 0.0,
		"tracked_process_ms": 0.0,
		"tracked_physics_ms": 0.0,
		"untracked_process_ms": 0.0,
		"untracked_physics_ms": 0.0,
		"fps": 0,
		"frames": 0,
		"phys_frames": 0,
		"draws": 0,
		"scene_nodes": 0,
		"process_items": [],
		"physics_items": [],
		"ai_items": [],
		"combat_items": [],
		"count_items": [],
		"engine_process_items": [],
	}
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("fps="):
			result["fps"] = int(round(_extract_float_after(line, "fps=")))
			result["frames"] = int(round(_extract_float_after(line, "frames=")))
			result["phys_frames"] = int(round(_extract_float_after(line, "phys_frames=")))
		elif line.begins_with("process="):
			result["process_ms"] = _extract_float_after(line, "process=")
			result["physics_ms"] = _extract_float_after(line, "physics=")
		elif line.begins_with("tracked proc="):
			result["tracked_process_ms"] = _extract_float_after(line, "tracked proc=")
			result["untracked_process_ms"] = _extract_float_after(line, "untracked~")
		elif line.begins_with("tracked phys="):
			result["tracked_physics_ms"] = _extract_float_after(line, "tracked phys=")
			result["untracked_physics_ms"] = _extract_float_after(line, "untracked~")
		elif line.begins_with("script.process "):
			result["process_items"] = _parse_metric_items(line.trim_prefix("script.process "))
		elif line.begins_with("script.physics "):
			result["physics_items"] = _parse_metric_items(line.trim_prefix("script.physics "))
		elif line.begins_with("script.ai "):
			result["ai_items"] = _parse_metric_items(line.trim_prefix("script.ai "))
		elif line.begins_with("script.combat "):
			result["combat_items"] = _parse_metric_items(line.trim_prefix("script.combat "))
		elif line.begins_with("script.count "):
			result["count_items"] = _parse_count_items(line.trim_prefix("script.count "))
		elif line.begins_with("engine.process "):
			result["engine_process_items"] = _parse_metric_items(line.trim_prefix("engine.process "))
		elif line.begins_with("scene_nodes="):
			result["scene_nodes"] = int(round(_extract_float_after(line, "scene_nodes=")))
			result["draws"] = int(round(_extract_float_after(line, "draws=")))
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


func _parse_count_items(payload: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for part in payload.split(", "):
		var eq_idx := part.find("=")
		if eq_idx <= 0:
			continue
		var metric := part.substr(0, eq_idx)
		var value_part := part.substr(eq_idx + 1)
		var count_per_frame := _extract_float_before(value_part, "/f")
		items.append({"metric": metric, "count_per_frame": count_per_frame})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("count_per_frame", 0.0)) > float(b.get("count_per_frame", 0.0))
	)
	return items


func _extract_float_after(text: String, token: String) -> float:
	var idx := text.find(token)
	if idx < 0:
		return 0.0
	var tail := text.substr(idx + token.length())
	var num := ""
	for i in range(tail.length()):
		var ch := tail[i]
		if ch == "-" or ch == "+" or ch == "." or (ch >= "0" and ch <= "9"):
			num += ch
			continue
		break
	return float(num) if num.is_valid_float() else 0.0


func _extract_float_before(text: String, token: String) -> float:
	var idx := text.find(token)
	var number_str := text if idx < 0 else text.substr(0, idx)
	number_str = number_str.strip_edges()
	return float(number_str) if number_str.is_valid_float() else 0.0


func _capture_collapsed_state() -> void:
	var root := tree.get_root()
	if root == null:
		return
	_collapsed_paths.clear()
	_capture_item_state_recursive(root, "")


func _capture_item_state_recursive(item: TreeItem, parent_path: String) -> void:
	var child := item.get_first_child()
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


func _process_parent_key(metric: String) -> String:
	if metric.ends_with(".total"):
		return metric.trim_suffix(".total")
	return metric.get_slice(".", 0) + "." + metric.get_slice(".", 1)
