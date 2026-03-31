extends Node

const FIRST_ENTRY_SPAWN_POINT := preload("res://game/world/spawn/first_entry_spawn_point.gd")
const Y_SORTING := preload("res://core/render/y_sorting.gd")
const Y_SORT_DEBUG_OVERLAY := preload("res://core/render/y_sort_debug_overlay.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")

@onready var zone_container: Node = $"../ZoneContainer"
@onready var world_root: Node = $".."

var player: Node2D
var current_target: Node = null

@export var use_cam_screen_center_for_world_math: bool = true
@export var debug_targeting_clicks: bool = false
@export var allow_corpse_targeting: bool = true
@export var debug_world_probe_under_mouse: bool = false
@export var debug_draw_y_sort_markers: bool = false
@export var debug_draw_tilemap_y_sort_markers: bool = false
@export var debug_perf_metrics_enabled: bool = true
@export var debug_perf_metrics_interval_sec: float = 0.5
@export var debug_runtime_profiler_overlay_enabled: bool = true
@export var debug_runtime_profiler_interval_sec: float = 0.5
@export var debug_runtime_profiler_draw_on_screen: bool = false

# --- Save/Load runtime ---
var current_zone_path: String = ""
var _pending_override_pos: Vector2 = Vector2.ZERO
var _has_override_pos: bool = false

var _save_debounce: Timer
var _autosave: Timer
var _save_pending: bool = false
var _has_loaded_character: bool = false
var _active_y_sort_host: Node2D = null
var _tree_node_added_connected: bool = false
var _y_sort_debug_overlay: Node2D = null
var _y_sort_debug_canvas: CanvasLayer = null
var _runtime_profiler_canvas: CanvasLayer = null
var _runtime_profiler_label: Label = null
var _player_sort_pivot: Node2D = null
var _entity_sort_pivots: Dictionary = {} # int(instance_id) -> Node2D pivot
var _node_requires_sort_pivot_cache: Dictionary = {} # int(instance_id) -> bool
var _entity_pivot_last_node_global: Dictionary = {} # int(instance_id) -> Vector2
var _perf_metrics_elapsed: float = 0.0
var _perf_frames_collected: int = 0
var _perf_sync_player_usec_accum: int = 0
var _perf_sync_entities_usec_accum: int = 0
var _perf_process_ms_accum: float = 0.0
var _perf_physics_ms_accum: float = 0.0
var _perf_last_interval_sec: float = 0.0
var _perf_last_avg_sync_player_ms: float = 0.0
var _perf_last_avg_sync_entities_ms: float = 0.0
var _perf_last_avg_process_ms: float = 0.0
var _perf_last_avg_physics_ms: float = 0.0
var _perf_last_entities_count: int = 0
var _perf_last_pivots_count: int = 0
var _perf_last_process_nodes_count: int = 0
var _perf_last_physics_nodes_count: int = 0
var _perf_last_player_nodes_count: int = 0
var _perf_last_mob_nodes_count: int = 0
var _perf_last_npc_nodes_count: int = 0
var _perf_last_projectile_nodes_count: int = 0
var _perf_last_runtime_process_line: String = "script.process=n/a"
var _perf_last_runtime_physics_line: String = "script.physics=n/a"
var _perf_last_runtime_ai_line: String = "script.ai=n/a"
var _perf_last_frames_count: int = 0
var _perf_last_physics_frames_count: int = 0
var _perf_last_tracked_process_ms_f: float = 0.0
var _perf_last_tracked_physics_ms_f: float = 0.0
var _perf_last_tracked_ai_ms_f: float = 0.0
var _perf_interval_physics_frame_cursor: int = -1


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		push_error("Player not found in group 'player'.")
		return

	# --- save timers ---
	_save_debounce = Timer.new()
	_save_debounce.one_shot = true
	_save_debounce.wait_time = 0.6
	add_child(_save_debounce)
	_save_debounce.timeout.connect(_flush_save)

	_autosave = Timer.new()
	_autosave.one_shot = false
	_autosave.wait_time = 20.0
	add_child(_autosave)
	_autosave.timeout.connect(_autosave_tick)
	_autosave.start()

	# --- load character state into world ---
	_load_character_into_world()
	if _has_loaded_character:
		call_deferred("_emit_player_spawned")
	call_deferred("_ensure_y_sort_debug_overlay")
	call_deferred("_ensure_runtime_profiler_overlay")


func _process(delta: float) -> void:
	var t_process_total := Time.get_ticks_usec()
	var t0 := Time.get_ticks_usec()
	_sync_player_sort_pivot()
	var t1 := Time.get_ticks_usec()
	_sync_entity_sort_pivots()
	var t2 := Time.get_ticks_usec()
	FRAME_PROFILER.add_usec("process.gm.sync_player_sort", t1 - t0)
	FRAME_PROFILER.add_usec("process.gm.sync_entity_sorts", t2 - t1)
	FRAME_PROFILER.add_usec("process.gm.total", Time.get_ticks_usec() - t_process_total)
	if debug_perf_metrics_enabled or debug_runtime_profiler_overlay_enabled:
		_collect_perf_metrics(delta, t1 - t0, t2 - t1)


func _collect_perf_metrics(delta: float, sync_player_usec: int, sync_entities_usec: int) -> void:
	_perf_metrics_elapsed += max(0.0, delta)
	_perf_frames_collected += 1
	_perf_sync_player_usec_accum += max(0, sync_player_usec)
	_perf_sync_entities_usec_accum += max(0, sync_entities_usec)
	_perf_process_ms_accum += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_perf_physics_ms_accum += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	if _perf_interval_physics_frame_cursor < 0:
		_perf_interval_physics_frame_cursor = Engine.get_physics_frames()
	var interval: float = max(0.25, debug_perf_metrics_interval_sec)
	if debug_runtime_profiler_overlay_enabled:
		interval = min(interval, max(0.25, debug_runtime_profiler_interval_sec))
	if _perf_metrics_elapsed < interval:
		return
	var frames: int = max(1, _perf_frames_collected)
	var avg_sync_player_ms := float(_perf_sync_player_usec_accum) / 1000.0 / float(frames)
	var avg_sync_entities_ms := float(_perf_sync_entities_usec_accum) / 1000.0 / float(frames)
	var avg_process_ms := _perf_process_ms_accum / float(frames)
	var avg_physics_ms := _perf_physics_ms_accum / float(frames)
	var current_physics_frames: int = Engine.get_physics_frames()
	var physics_frames: int = max(1, current_physics_frames - max(0, _perf_interval_physics_frame_cursor))
	var total_entities := get_tree().get_nodes_in_group("y_sort_entities").size()
	var pivot_count := _entity_sort_pivots.size()
	_collect_runtime_node_breakdown()
	_perf_last_interval_sec = _perf_metrics_elapsed
	_perf_last_frames_count = frames
	_perf_last_physics_frames_count = physics_frames
	_perf_last_avg_sync_player_ms = avg_sync_player_ms
	_perf_last_avg_sync_entities_ms = avg_sync_entities_ms
	_perf_last_avg_process_ms = avg_process_ms
	_perf_last_avg_physics_ms = avg_physics_ms
	_perf_last_entities_count = total_entities
	_perf_last_pivots_count = pivot_count
	var runtime_samples: Dictionary = FRAME_PROFILER.consume_stats()
	_update_runtime_tracking_totals(runtime_samples, frames, physics_frames)
	_perf_last_runtime_process_line = _build_runtime_breakdown_line(
		runtime_samples,
		frames,
		"script.process",
		func(key: String) -> bool:
			return key.begins_with("process."),
		frames,
		6
	)
	_perf_last_runtime_physics_line = _build_runtime_breakdown_line(
		runtime_samples,
		frames,
		"script.physics",
		func(key: String) -> bool:
			return key.find(".physics.") != -1,
		physics_frames,
		5
	)
	_perf_last_runtime_ai_line = _build_runtime_breakdown_line(
		runtime_samples,
		frames,
		"script.ai",
		func(key: String) -> bool:
			return key.find(".ai.") != -1,
		physics_frames,
		5
	)
	if debug_perf_metrics_enabled:
		print(
			"[Perf][GameManager] interval=%.2fs frames=%d avg_sync_player=%.3fms avg_sync_entities=%.3fms y_sort_entities=%d pivots=%d process_nodes=%d physics_nodes=%d players=%d mobs=%d npcs=%d projectiles=%d y_sort_dbg=%s tile_dbg=%s"
			% [
				_perf_metrics_elapsed,
				frames,
				avg_sync_player_ms,
				avg_sync_entities_ms,
				total_entities,
				pivot_count,
				_perf_last_process_nodes_count,
				_perf_last_physics_nodes_count,
				_perf_last_player_nodes_count,
				_perf_last_mob_nodes_count,
				_perf_last_npc_nodes_count,
				_perf_last_projectile_nodes_count,
				str(debug_draw_y_sort_markers),
				str(debug_draw_tilemap_y_sort_markers),
			]
		)
	if debug_runtime_profiler_overlay_enabled:
		_update_runtime_profiler_overlay()
	_perf_metrics_elapsed = 0.0
	_perf_frames_collected = 0
	_perf_sync_player_usec_accum = 0
	_perf_sync_entities_usec_accum = 0
	_perf_process_ms_accum = 0.0
	_perf_physics_ms_accum = 0.0
	_perf_interval_physics_frame_cursor = current_physics_frames


func _collect_runtime_node_breakdown() -> void:
	var process_nodes := 0
	var physics_nodes := 0
	var player_nodes := 0
	var mob_nodes := 0
	var npc_nodes := 0
	var projectile_nodes := 0
	var y_sort_entities := get_tree().get_nodes_in_group("y_sort_entities")
	for entity in y_sort_entities:
		if entity == null or not is_instance_valid(entity) or not (entity is Node):
			continue
		var node := entity as Node
		if node.is_processing():
			process_nodes += 1
		if node.is_physics_processing():
			physics_nodes += 1
		var script: Script = node.get_script()
		if script == null:
			continue
		var script_path := String(script.resource_path)
		if script_path.ends_with("game/characters/player/player.gd"):
			player_nodes += 1
		elif script_path.find("game/characters/mobs/") != -1:
			mob_nodes += 1
		elif script_path.find("game/characters/npcs/") != -1:
			npc_nodes += 1
		elif script_path.find("projectiles/") != -1:
			projectile_nodes += 1
	_perf_last_process_nodes_count = process_nodes
	_perf_last_physics_nodes_count = physics_nodes
	_perf_last_player_nodes_count = player_nodes
	_perf_last_mob_nodes_count = mob_nodes
	_perf_last_npc_nodes_count = npc_nodes
	_perf_last_projectile_nodes_count = projectile_nodes


func _build_runtime_breakdown_line(
	samples: Dictionary,
	frames: int,
	label: String,
	key_filter: Callable,
	frame_divisor: int,
	max_parts: int
) -> String:
	if samples.is_empty():
		return "%s=n/a" % label
	var frame_count: int = max(1, frames)
	var entries: Array[Dictionary] = []
	for key_v in samples.keys():
		var key: String = String(key_v)
		if not key_filter.call(key):
			continue
		var entry_v: Variant = samples.get(key, {})
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		entries.append(
			{
				"key": key,
				"frame_ms": float(entry.get("total_ms", 0.0)) / float(max(1, frame_divisor)),
				"total_ms": float(entry.get("total_ms", 0.0)),
				"avg_ms": float(entry.get("avg_ms", 0.0)),
				"samples": int(entry.get("samples", 0)),
			}
		)
	entries.sort_custom(_sort_runtime_breakdown_desc)
	var parts: Array[String] = []
	for item in entries:
		var key: String = String(item.get("key", ""))
		if key == "":
			continue
		var short_name: String = key.replace(".physics.", ".")
		var frame_ms: float = float(item.get("frame_ms", 0.0))
		var total_ms: float = float(item.get("total_ms", 0.0))
		var avg_ms: float = float(item.get("avg_ms", 0.0))
		var samples_count: int = int(item.get("samples", 0))
		parts.append("%s=%.3fms/f(avg %.3f x%d)" % [short_name, frame_ms, avg_ms, samples_count])
		if parts.size() >= max(1, max_parts):
			break
	if parts.is_empty():
		return "%s=n/a" % label
	return "%s %s" % [label, ", ".join(parts)]


func _sort_runtime_breakdown_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("frame_ms", 0.0)) > float(b.get("frame_ms", 0.0))


func _update_runtime_tracking_totals(samples: Dictionary, frames: int, physics_frames: int) -> void:
	var process_frame_count: int = max(1, frames)
	var physics_frame_count: int = max(1, physics_frames)
	var process_total: float = 0.0
	var physics_total: float = 0.0
	var ai_total: float = 0.0
	var physics_totals_by_ns: Dictionary = {}
	var physics_subtotals_by_ns: Dictionary = {}
	for key_v in samples.keys():
		var key: String = String(key_v)
		var entry_v: Variant = samples.get(key, {})
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var total_ms_process_f: float = float(entry.get("total_ms", 0.0)) / float(process_frame_count)
		var total_ms_physics_f: float = float(entry.get("total_ms", 0.0)) / float(physics_frame_count)
		if key.begins_with("process."):
			process_total += total_ms_process_f
		elif key.find(".physics.") != -1:
			var physics_ns: String = _extract_physics_namespace(key)
			if key.ends_with(".physics.total"):
				physics_totals_by_ns[physics_ns] = total_ms_physics_f
			else:
				var prev_subtotal: float = float(physics_subtotals_by_ns.get(physics_ns, 0.0))
				physics_subtotals_by_ns[physics_ns] = prev_subtotal + total_ms_physics_f
		elif key.find(".ai.") != -1:
			ai_total += total_ms_physics_f
	for ns_v in physics_subtotals_by_ns.keys():
		var ns: String = String(ns_v)
		if physics_totals_by_ns.has(ns):
			continue
		physics_total += float(physics_subtotals_by_ns.get(ns, 0.0))
	for ns_v in physics_totals_by_ns.keys():
		var ns: String = String(ns_v)
		physics_total += float(physics_totals_by_ns.get(ns, 0.0))
	_perf_last_tracked_process_ms_f = process_total
	_perf_last_tracked_physics_ms_f = physics_total
	_perf_last_tracked_ai_ms_f = ai_total


func _extract_physics_namespace(key: String) -> String:
	var split_parts: PackedStringArray = key.split(".physics.")
	if split_parts.is_empty():
		return key
	return String(split_parts[0])


func _ensure_runtime_profiler_overlay() -> void:
	if world_root == null:
		return
	if not debug_runtime_profiler_overlay_enabled:
		if _runtime_profiler_canvas != null and is_instance_valid(_runtime_profiler_canvas):
			_runtime_profiler_canvas.visible = false
		return
	if _runtime_profiler_canvas == null or not is_instance_valid(_runtime_profiler_canvas):
		_runtime_profiler_canvas = CanvasLayer.new()
		_runtime_profiler_canvas.name = "__runtime_profiler_canvas"
		_runtime_profiler_canvas.layer = 110
		world_root.add_child.call_deferred(_runtime_profiler_canvas)
	if _runtime_profiler_label == null or not is_instance_valid(_runtime_profiler_label):
		_runtime_profiler_label = Label.new()
		_runtime_profiler_label.name = "__runtime_profiler_label"
		_runtime_profiler_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_runtime_profiler_label.offset_left = 16.0
		_runtime_profiler_label.offset_bottom = -16.0
		_runtime_profiler_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_runtime_profiler_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_runtime_profiler_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_runtime_profiler_label.add_theme_font_size_override("font_size", 14)
		_runtime_profiler_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 0.95))
		_runtime_profiler_canvas.add_child.call_deferred(_runtime_profiler_label)
	_runtime_profiler_canvas.visible = debug_runtime_profiler_draw_on_screen
	_update_runtime_profiler_overlay()


func _update_runtime_profiler_overlay() -> void:
	if not debug_runtime_profiler_overlay_enabled:
		return
	if _runtime_profiler_label == null or not is_instance_valid(_runtime_profiler_label):
		return
	var viewport_size: Vector2i = get_viewport().get_visible_rect().size
	var max_overlay_width: float = clamp(float(viewport_size.x) * 0.60, 540.0, 1280.0)
	_runtime_profiler_label.custom_minimum_size.x = max_overlay_width
	var fps: int = int(round(Engine.get_frames_per_second()))
	var tree_nodes: int = get_tree().get_node_count()
	var target_state: String = "none"
	var process_ms: float = _perf_last_avg_process_ms
	var physics_ms: float = _perf_last_avg_physics_ms
	var node_count_monitor: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if current_target != null and is_instance_valid(current_target):
		target_state = String(current_target.name)
	var process_ms_per_node: float = 0.0
	if _perf_last_process_nodes_count > 0:
		process_ms_per_node = process_ms / float(_perf_last_process_nodes_count)
	var physics_ms_per_node: float = 0.0
	if _perf_last_physics_nodes_count > 0:
		physics_ms_per_node = physics_ms / float(_perf_last_physics_nodes_count)
	var untracked_process_ms: float = max(0.0, process_ms - _perf_last_tracked_process_ms_f)
	var untracked_physics_ms: float = max(0.0, physics_ms - _perf_last_tracked_physics_ms_f)
	# Most AI timers are emitted from mob/NPC physics ticks.
	var tracked_physics_with_ai_ms: float = _perf_last_tracked_physics_ms_f + _perf_last_tracked_ai_ms_f
	var untracked_physics_with_ai_ms: float = max(0.0, physics_ms - tracked_physics_with_ai_ms)
	var tracked_process_coverage_pct: float = 0.0
	if process_ms > 0.0:
		tracked_process_coverage_pct = clamp((_perf_last_tracked_process_ms_f / process_ms) * 100.0, 0.0, 100.0)
	var tracked_physics_coverage_pct: float = 0.0
	if physics_ms > 0.0:
		tracked_physics_coverage_pct = clamp((_perf_last_tracked_physics_ms_f / physics_ms) * 100.0, 0.0, 100.0)
	var tracked_physics_with_ai_coverage_pct: float = 0.0
	if physics_ms > 0.0:
		tracked_physics_with_ai_coverage_pct = clamp((tracked_physics_with_ai_ms / physics_ms) * 100.0, 0.0, 100.0)
	_runtime_profiler_label.text = (
		"[Runtime Profiler]\n"
		+ "fps=%d interval=%.2fs frames=%d phys_frames=%d\n" % [fps, _perf_last_interval_sec, _perf_last_frames_count, _perf_last_physics_frames_count]
		+ "process=%.2fms physics=%.2fms\n" % [process_ms, physics_ms]
		+ "proc/node=%.3fms phys/node=%.3fms\n" % [process_ms_per_node, physics_ms_per_node]
		+ "tracked proc=%.2fms/f untracked~%.2fms\n" % [_perf_last_tracked_process_ms_f, untracked_process_ms]
		+ "tracked phys=%.2fms/f untracked~%.2fms\n" % [_perf_last_tracked_physics_ms_f, untracked_physics_ms]
		+ "tracked ai=%.2fms/f phys(+ai)=%.2fms/f untracked~%.2fms\n" % [_perf_last_tracked_ai_ms_f, tracked_physics_with_ai_ms, untracked_physics_with_ai_ms]
		+ "coverage proc=%.1f%% phys=%.1f%% phys(+ai)=%.1f%%\n" % [tracked_process_coverage_pct, tracked_physics_coverage_pct, tracked_physics_with_ai_coverage_pct]
		+ "gm.sync_player=%.3fms\n" % _perf_last_avg_sync_player_ms
		+ "gm.sync_entities=%.3fms\n" % _perf_last_avg_sync_entities_ms
		+ "y_sort_entities=%d pivots=%d\n" % [_perf_last_entities_count, _perf_last_pivots_count]
		+ "proc_nodes=%d phys_nodes=%d\n" % [_perf_last_process_nodes_count, _perf_last_physics_nodes_count]
		+ "players=%d mobs=%d npcs=%d proj=%d\n" % [_perf_last_player_nodes_count, _perf_last_mob_nodes_count, _perf_last_npc_nodes_count, _perf_last_projectile_nodes_count]
		+ "%s\n" % _perf_last_runtime_process_line
		+ "%s\n" % _perf_last_runtime_physics_line
		+ "%s\n" % _perf_last_runtime_ai_line
		+ "scene_nodes=%d monitor_nodes=%d draws=%d\n" % [tree_nodes, node_count_monitor, draw_calls]
		+ "target=%s" % target_state
	)
	var min_size: Vector2 = _runtime_profiler_label.get_minimum_size()
	_runtime_profiler_label.offset_top = _runtime_profiler_label.offset_bottom - min_size.y

func _get_world_screen_center(cam: Camera2D) -> Vector2:
	if cam == null:
		return Vector2.ZERO
	if use_cam_screen_center_for_world_math:
		return cam.get_screen_center_position()
	return cam.global_position


func _ensure_y_sort_debug_overlay() -> void:
	if world_root == null:
		return
	if _y_sort_debug_overlay != null and is_instance_valid(_y_sort_debug_overlay):
		return
	if _y_sort_debug_canvas == null or not is_instance_valid(_y_sort_debug_canvas):
		_y_sort_debug_canvas = CanvasLayer.new()
		_y_sort_debug_canvas.name = "__y_sort_debug_canvas"
		_y_sort_debug_canvas.layer = 100
		world_root.add_child.call_deferred(_y_sort_debug_canvas)
	_y_sort_debug_overlay = Y_SORT_DEBUG_OVERLAY.new()
	_y_sort_debug_overlay.name = "__y_sort_debug_overlay"
	_y_sort_debug_overlay.set("manager", self)
	_y_sort_debug_canvas.add_child.call_deferred(_y_sort_debug_overlay)



func _exit_tree() -> void:
	# Ensure we don't lose the last known zone/position/stats when leaving the world scene.
	# This is especially important when the player exits to menu or the window closes.
	save_now()


func _notification(what: int) -> void:
	# Catch OS-level close requests (Alt+F4 / window close button)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


# Godot can store scene references as uid://... in some situations (or old saves).
# We keep saves stable by converting unknown UIDs back to a real path.
func _sanitize_zone_path(zone_scene_path: String) -> String:
	if zone_scene_path == null:
		return "res://game/world/zones/Zone_01.tscn"
	var p: String = String(zone_scene_path)
	if p.begins_with("uid://"):
		# If .godot cache was deleted (recommended), UID mapping may be missing.
		# Fall back to default zone instead of crashing.
		return "res://game/world/zones/Zone_01.tscn"
	return p


func _load_character_into_world() -> void:
	if not has_node("/root/AppState"):
		return

	var data: Dictionary = AppState.selected_character_data
	if data.is_empty():
		# Защиты ты просил отложить — просто ничего не делаем.
		return
	_has_loaded_character = true

	# 1) Зона + точка входа
	var zone_path: String = String(data.get("zone", "res://game/world/zones/Zone_01.tscn"))
	zone_path = _sanitize_zone_path(zone_path)
	if zone_path == "":
		zone_path = "res://game/world/zones/Zone_01.tscn"

	var spawn_name: String = "SpawnPoint"

	# 2) Позиция: если позиции нет, пробуем last_world_pos; первый вход определяем
	# по признакам сохранения, а не только по (0,0), чтобы при сбое не телепортировать
	# уже существующего персонажа в точку первого входа.
	var pos_v: Variant = data.get("pos", null)
	if not (pos_v is Dictionary):
		pos_v = data.get("last_world_pos", null)
	_has_override_pos = false
	_pending_override_pos = Vector2.ZERO
	var is_first_entry: bool = _is_first_world_entry(data)
	var restored_pos: Vector2 = _extract_non_zero_pos(pos_v)
	if restored_pos != Vector2.ZERO:
		is_first_entry = false
		_has_override_pos = true
		_pending_override_pos = restored_pos

	if is_first_entry:
		var faction_id := String(data.get("faction", "blue")).to_lower()
		var first_spawn: Dictionary = _find_first_entry_spawn_for_faction(faction_id)
		if not first_spawn.is_empty():
			zone_path = String(first_spawn.get("zone_path", zone_path))
			spawn_name = String(first_spawn.get("spawn_name", spawn_name))

	current_zone_path = zone_path

	# 3) Загружаем зону
	load_zone(zone_path, spawn_name)

	# 4) Применяем статы/инвентарь
	if player.has_method("apply_character_data"):
		player.call("apply_character_data", data)

	# 5) Сохраним состояние входа (debounce)
	request_save("enter_world")


func _extract_non_zero_pos(pos_v: Variant) -> Vector2:
	if pos_v is Dictionary:
		var pos_d: Dictionary = pos_v as Dictionary
		var x: float = float(pos_d.get("x", 0.0))
		var y: float = float(pos_d.get("y", 0.0))
		if not (is_zero_approx(x) and is_zero_approx(y)):
			return Vector2(x, y)
	return Vector2.ZERO


func _is_first_world_entry(data: Dictionary) -> bool:
	# Жесткий флаг: если уже входил в мир, повторно first-entry не запускаем.
	if bool(data.get("world_entered_once", false)):
		return false

	# Надежные признаки прогресса. Не учитываем equipment/spellbook,
	# т.к. стартовый персонаж может иметь их с момента создания.
	if int(data.get("level", 1)) > 1:
		return false
	if int(data.get("xp", 0)) > 0:
		return false

	var inventory_v: Variant = data.get("inventory", null)
	if inventory_v is Dictionary:
		var inventory: Dictionary = inventory_v as Dictionary
		if int(inventory.get("gold", 0)) > 0:
			return false
		var slots_v: Variant = inventory.get("slots", [])
		if slots_v is Array:
			for slot_v in (slots_v as Array):
				if slot_v is Dictionary and not (slot_v as Dictionary).is_empty():
					return false

	return true


func _emit_player_spawned() -> void:
	if player == null or not is_instance_valid(player):
		return
	var flow_router := get_node_or_null("/root/FlowRouter")
	if flow_router != null and flow_router.has_method("notify_player_spawned"):
		flow_router.call("notify_player_spawned", player, self)
		if OS.is_debug_build():
			print("[FLOW] player_spawned emitted. player=", player, " class=", player.get("class_id"))


func _find_first_entry_spawn_for_faction(faction_id: String) -> Dictionary:
	var normalized := faction_id.strip_edges().to_lower()
	if normalized != "red":
		normalized = "blue"
	var zones_dir := DirAccess.open("res://game/world/zones")
	if zones_dir == null:
		push_error("[FirstEntry] Cannot open zones directory")
		return {}
	zones_dir.list_dir_begin()
	var file_name := zones_dir.get_next()
	while file_name != "":
		if not zones_dir.current_is_dir() and file_name.ends_with(".tscn"):
			var zone_path := "res://game/world/zones/" + file_name
			var zone_scene := load(zone_path) as PackedScene
			if zone_scene != null:
				var root := zone_scene.instantiate()
				var marker := _find_first_entry_marker_in_tree(root, normalized)
				if marker != null:
					var result := {"zone_path": zone_path, "spawn_name": String(marker.name)}
					root.free()
					zones_dir.list_dir_end()
					return result
				root.free()
		file_name = zones_dir.get_next()
	zones_dir.list_dir_end()
	push_error("[FirstEntry] Spawn marker for faction '%s' not found" % normalized)
	return {}

func _find_first_entry_marker_in_tree(root: Node, faction_id: String) -> Marker2D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D and current.get_script() == FIRST_ENTRY_SPAWN_POINT:
			if current.has_method("get_faction_id") and String(current.call("get_faction_id")).to_lower() == faction_id:
				return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


# ---------------------------
# Save API (debounced)
# ---------------------------
func request_save(_reason: String) -> void:
	_save_pending = true
	_save_debounce.start()

func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	_do_save_now()

func _autosave_tick() -> void:
	request_save("autosave")

func _do_save_now() -> void:
	if not has_node("/root/AppState"):
		return
	if AppState.selected_character_id == "":
		return
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("export_character_data"):
		return

	var data: Dictionary = player.call("export_character_data")

	# зона
	if current_zone_path != "":
		data["zone"] = current_zone_path
	data["world_entered_once"] = true
	data["last_world_zone"] = current_zone_path
	data["last_world_pos"] = {"x": float(player.global_position.x), "y": float(player.global_position.y)}

	AppState.save_selected_character(data)


# ---------------------------
# Zone loading
# ---------------------------
func load_zone(zone_scene_path: String, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene_path == "" or zone_scene_path == null:
		push_error("Zone path is empty.")
		return

	current_zone_path = zone_scene_path
	request_save("zone_change")

	# Wait a frame so physics flushing doesn't explode
	call_deferred("_load_zone_deferred", zone_scene_path, spawn_name)


func _load_zone_deferred(zone_scene_path: String, spawn_name: String) -> void:
	var zone_scene: PackedScene = load(zone_scene_path)
	if zone_scene == null:
		push_error("Failed to load zone: " + zone_scene_path)
		return

	# Clear previous zone
	_detach_player_from_zone_for_reload()
	for child in zone_container.get_children():
		child.queue_free()

	# Instantiate new zone
	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	# Move player to spawn
	var resolved_spawn: Marker2D = _resolve_spawn_marker(new_zone, spawn_name)
	if resolved_spawn != null:
		player.global_position = resolved_spawn.global_position
	else:
		push_error("Zone '%s' has no valid spawn marker. Keeping current player position." % zone_scene_path)

	# Override position if saved (not first entry)
	if _has_override_pos:
		player.global_position = _pending_override_pos
		_has_override_pos = false

	# Sync camera limits with the loaded zone so large maps keep player visible.
	_apply_camera_limits_from_zone(new_zone)
	_attach_player_to_zone_sort_host(new_zone)

	# Optional: target becomes invalid when changing zones
	clear_target()




func _detach_player_from_zone_for_reload() -> void:
	if player == null or not is_instance_valid(player):
		return
	if world_root == null:
		return
	if _player_sort_pivot != null and is_instance_valid(_player_sort_pivot):
		if player.get_parent() == _player_sort_pivot:
			player.reparent(world_root, true)
		if _player_sort_pivot.get_parent() != null:
			_player_sort_pivot.queue_free()
		_player_sort_pivot = null
	if player.get_parent() == world_root:
		return
	player.reparent(world_root, true)


func _attach_player_to_zone_sort_host(zone_root: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if zone_root == null:
		return
	var host: Node2D = _find_zone_sort_host(zone_root)
	if host == null:
		return
	host.y_sort_enabled = true
	var entity_host := _ensure_y_sort_runtime_layer(host)
	if _node_has_native_y_sort_origin(player):
		if _player_sort_pivot != null and is_instance_valid(_player_sort_pivot):
			_player_sort_pivot.queue_free()
		_player_sort_pivot = null
		if player.get_parent() != entity_host:
			player.reparent(entity_host, true)
	else:
		var sort_pivot := _ensure_player_sort_pivot(entity_host)
		if player.get_parent() != sort_pivot:
			player.reparent(sort_pivot, true)
	player.top_level = false
	player.y_sort_enabled = false
	player.z_as_relative = true
	player.z_index = 0
	_sync_player_sort_pivot()


func _ensure_player_sort_pivot(entity_host: Node2D) -> Node2D:
	if entity_host == null:
		return null
	var pivot := entity_host.get_node_or_null("__player_sort_pivot") as Node2D
	if pivot == null:
		pivot = Node2D.new()
		pivot.name = "__player_sort_pivot"
		entity_host.add_child(pivot)
	# Keep pivot as a pure anchor node.
	# If y_sort is enabled here, renderer may re-sort its children by their own Y,
	# which can effectively bypass the anchor semantics we need for the player branch.
	pivot.y_sort_enabled = false
	pivot.z_as_relative = true
	pivot.z_index = int(entity_host.z_index)
	_player_sort_pivot = pivot
	return pivot


func _sync_player_sort_pivot() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _node_has_native_y_sort_origin(player):
		return
	if _player_sort_pivot == null or not is_instance_valid(_player_sort_pivot):
		return
	if player.get_parent() != _player_sort_pivot:
		return
	var desired_player_global := player.global_position
	var anchor_global := desired_player_global
	if player.has_method("get_sort_anchor_global"):
		var anchor_v: Variant = player.call("get_sort_anchor_global")
		if anchor_v is Vector2:
			anchor_global = anchor_v as Vector2
	_player_sort_pivot.global_position = anchor_global
	if player.global_position != desired_player_global:
		player.global_position = desired_player_global


func _node_has_native_y_sort_origin(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method("set_y_sort_origin"):
		return true
	if node.has_method("get_y_sort_origin"):
		return true
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			return true
	return false


func _ensure_y_sort_runtime_layer(host: Node2D) -> Node2D:
	var runtime := host.get_node_or_null("__y_sort_runtime") as Node2D
	if runtime == null:
		runtime = Node2D.new()
		runtime.name = "__y_sort_runtime"
		runtime.y_sort_enabled = true
		runtime.z_index = int(host.z_index)
		host.add_child(runtime)
	if not bool(host.get_meta("__y_sort_runtime_flattened", false)):
		var tile_layers: Array[TileMapLayer] = []
		_collect_tile_layers_for_runtime(host, runtime, tile_layers)
		for layer in tile_layers:
			if layer.get_parent() != runtime:
				layer.reparent(runtime, true)
		var sortable_nodes: Array[Node2D] = []
		_collect_sortable_nodes_for_runtime(host, runtime, sortable_nodes)
		for sortable in sortable_nodes:
			_maybe_promote_node_to_runtime(sortable, runtime)
		host.set_meta("__y_sort_runtime_flattened", true)
	_active_y_sort_host = host
	if not _tree_node_added_connected:
		var cb := Callable(self, "_on_tree_node_added")
		if not get_tree().node_added.is_connected(cb):
			get_tree().node_added.connect(cb)
		_tree_node_added_connected = true
	return runtime


func _collect_tile_layers_for_runtime(node: Node, runtime: Node2D, out_layers: Array[TileMapLayer]) -> void:
	if node == runtime:
		return
	for child in node.get_children():
		if child == runtime:
			continue
		if child is TileMapLayer:
			out_layers.append(child as TileMapLayer)
		elif child is Node:
			_collect_tile_layers_for_runtime(child as Node, runtime, out_layers)


func _collect_sortable_nodes_for_runtime(node: Node, runtime: Node2D, out_nodes: Array[Node2D]) -> void:
	if node == runtime:
		return
	for child in node.get_children():
		if child == runtime:
			continue
		if child is Node2D:
			out_nodes.append(child as Node2D)
		if child is Node:
			_collect_sortable_nodes_for_runtime(child as Node, runtime, out_nodes)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _active_y_sort_host == null or not is_instance_valid(_active_y_sort_host):
		return
	if not _active_y_sort_host.is_ancestor_of(node):
		return
	# Godot can emit node_added while the parent is still mutating children.
	# Deferring avoids "parent is busy adding/removing children" reparent errors.
	call_deferred("_promote_node_to_runtime_deferred", node)


func _promote_node_to_runtime_deferred(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _active_y_sort_host == null or not is_instance_valid(_active_y_sort_host):
		return
	if not _active_y_sort_host.is_ancestor_of(node):
		return
	var runtime := _active_y_sort_host.get_node_or_null("__y_sort_runtime") as Node2D
	if runtime == null:
		return
	_maybe_promote_node_to_runtime(node, runtime)


func _maybe_promote_node_to_runtime(node: Node, runtime: Node2D) -> void:
	if node == runtime:
		return
	if node is TileMapLayer:
		if node.get_parent() != runtime:
			(node as TileMapLayer).reparent(runtime, true)
		return
	if not (node is Node2D):
		return
	var n2d := node as Node2D
	var direct_parent := n2d.get_parent() as Node2D
	if direct_parent != null and String(direct_parent.name).begins_with("__sort_pivot_"):
		# Node is already managed by a runtime anchor pivot; avoid re-promotion ping-pong.
		return
	if player != null and is_instance_valid(player) and n2d == player:
		if _node_has_native_y_sort_origin(player):
			if n2d.get_parent() != runtime:
				n2d.reparent(runtime, true)
			return
		if _player_sort_pivot != null and is_instance_valid(_player_sort_pivot):
			if n2d.get_parent() != _player_sort_pivot:
				n2d.reparent(_player_sort_pivot, true)
		return
	if _has_y_sort_entity_ancestor(n2d):
		return
	if _should_skip_nested_runtime_promotion(n2d):
		return
	var node_name := String(n2d.name).to_lower()
	if node_name == "decor" or node_name == "spawner groups" or node_name == "__y_sort_runtime":
		return
	var should_promote: bool = false
	should_promote = _is_runtime_promotion_candidate(n2d)
	if should_promote and n2d.get_parent() != runtime:
		n2d.reparent(runtime, true)
	if _node_requires_sort_pivot(n2d):
		_attach_node_to_entity_sort_pivot(n2d, runtime)
	_try_sync_node_y_sort_origin_from_world_collider(n2d)


func _node_requires_sort_pivot(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var key := node.get_instance_id()
	if _node_requires_sort_pivot_cache.has(key):
		return bool(_node_requires_sort_pivot_cache[key])
	if player != null and is_instance_valid(player) and node == player:
		_node_requires_sort_pivot_cache[key] = false
		return false
	if not node.has_method("get_sort_anchor_global"):
		_node_requires_sort_pivot_cache[key] = false
		return false
	var requires_pivot := not _node_has_native_y_sort_origin(node)
	_node_requires_sort_pivot_cache[key] = requires_pivot
	return requires_pivot


func _attach_node_to_entity_sort_pivot(node: Node2D, runtime: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if runtime == null or not is_instance_valid(runtime):
		return
	if not _node_requires_sort_pivot(node):
		return
	var key := node.get_instance_id()
	var pivot := _entity_sort_pivots.get(key, null) as Node2D
	if pivot == null or not is_instance_valid(pivot):
		pivot = Node2D.new()
		pivot.name = "__sort_pivot_%d" % key
		pivot.y_sort_enabled = false
		pivot.z_as_relative = true
		pivot.z_index = int(runtime.z_index)
		runtime.add_child(pivot)
		_entity_sort_pivots[key] = pivot
	if node.get_parent() != pivot:
		node.reparent(pivot, true)
	node.top_level = false
	node.y_sort_enabled = false
	node.z_as_relative = true
	node.z_index = 0


func _sync_entity_sort_pivots() -> void:
	if _entity_sort_pivots.is_empty():
		return
	var stale_keys: Array[int] = []
	for key_v in _entity_sort_pivots.keys():
		var key := int(key_v)
		var pivot := _entity_sort_pivots.get(key, null) as Node2D
		if pivot == null or not is_instance_valid(pivot):
			stale_keys.append(key)
			continue
		var node := instance_from_id(key) as Node2D
		if node == null or not is_instance_valid(node):
			pivot.queue_free()
			stale_keys.append(key)
			_node_requires_sort_pivot_cache.erase(key)
			continue
		if not _node_requires_sort_pivot(node):
			if node.get_parent() == pivot and pivot.get_parent() != null:
				node.reparent(pivot.get_parent(), true)
			pivot.queue_free()
			stale_keys.append(key)
			_node_requires_sort_pivot_cache.erase(key)
			continue
		if node.get_parent() != pivot:
			node.reparent(pivot, true)
		var desired_node_global := node.global_position
		if _entity_pivot_last_node_global.has(key):
			var last_node_global_v: Variant = _entity_pivot_last_node_global.get(key)
			if last_node_global_v is Vector2:
				var last_node_global := last_node_global_v as Vector2
				if last_node_global.is_equal_approx(desired_node_global):
					continue
		var anchor_global := desired_node_global
		var anchor_v: Variant = node.call("get_sort_anchor_global")
		if anchor_v is Vector2:
			anchor_global = anchor_v as Vector2
		pivot.global_position = anchor_global
		if node.global_position != desired_node_global:
			node.global_position = desired_node_global
		_entity_pivot_last_node_global[key] = desired_node_global
	for stale in stale_keys:
		_entity_sort_pivots.erase(stale)
		_node_requires_sort_pivot_cache.erase(stale)
		_entity_pivot_last_node_global.erase(stale)


func _has_y_sort_entity_ancestor(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var parent := node.get_parent()
	while parent != null:
		if parent.is_in_group("y_sort_entities"):
			return true
		parent = parent.get_parent()
	return false


func _is_runtime_promotion_candidate(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var node_name := String(node.name).to_lower()
	if node.has_method("get_sort_anchor_global"):
		return true
	if node.is_in_group("y_sort_entities"):
		return true
	if node_name == "player":
		return true
	if node.get_node_or_null("CollisionProfile/WorldCollider") != null:
		return true
	if node.get_node_or_null("WorldCollider") != null:
		return true
	return false


func _should_skip_nested_runtime_promotion(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	var parent := node.get_parent()
	while parent != null:
		if parent is Node2D and _is_runtime_promotion_candidate(parent as Node2D):
			return true
		if parent == _active_y_sort_host:
			break
		parent = parent.get_parent()
	return false


func _try_sync_node_y_sort_origin_from_world_collider(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var world_collider := node.get_node_or_null("WorldCollider") as CollisionShape2D
	if world_collider == null:
		world_collider = node.get_node_or_null("CollisionProfile/WorldCollider") as CollisionShape2D
	if world_collider == null:
		return
	var origin_y := _compute_world_collider_sort_origin_y(node, world_collider)
	_apply_node_y_sort_origin(node, origin_y)


func _compute_world_collider_sort_origin_y(owner_node: Node2D, collider: CollisionShape2D) -> float:
	# Match debug green-diamond logic: collider center in global space, converted to owner local.
	if owner_node == null or not is_instance_valid(owner_node):
		return float(collider.position.y)
	return float(owner_node.to_local(collider.global_position).y)


func _apply_node_y_sort_origin(node: Node2D, origin_y: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var origin_i := int(round(origin_y))
	if node.has_method("set_y_sort_origin"):
		node.call("set_y_sort_origin", origin_i)
		return
	if node.has_method("get_y_sort_origin"):
		node.set("y_sort_origin", origin_i)
		return
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			node.set("y_sort_origin", origin_i)
			return
	node.set_meta("__debug_y_sort_origin_local", origin_i)


func _read_node_y_sort_origin_local(node: Node2D) -> Dictionary:
	var result := {
		"has_origin": false,
		"origin": 0.0,
		"source": "none",
	}
	if node == null or not is_instance_valid(node):
		return result
	if node.has_method("get_y_sort_origin"):
		result["has_origin"] = true
		result["origin"] = float(node.call("get_y_sort_origin"))
		result["source"] = "getter"
		return result
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			result["has_origin"] = true
			result["origin"] = float(node.get("y_sort_origin"))
			result["source"] = "property"
			return result
	if node.has_meta("__debug_y_sort_origin_local"):
		# Debug-only fallback: not guaranteed to be used by renderer sorting.
		result["has_origin"] = false
		result["origin"] = float(node.get_meta("__debug_y_sort_origin_local"))
		result["source"] = "meta"
	return result


func _find_zone_sort_host(zone_root: Node) -> Node2D:
	if zone_root == null:
		return null
	var stack: Array[Node] = [zone_root]
	var fallback_z50: Node2D = null
	var fallback_ysort: Node2D = null
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Node2D:
			var node2d := current as Node2D
			var node_name := String(current.name)
			if node_name == "z-level = 50, y-sort = true":
				return node2d
			if fallback_z50 == null and int(node2d.z_index) == 50:
				fallback_z50 = node2d
			if fallback_ysort == null and node2d.y_sort_enabled:
				fallback_ysort = node2d
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	if fallback_z50 != null:
		return fallback_z50
	return fallback_ysort


func _apply_camera_limits_from_zone(zone_root: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		return
	var bounds: Rect2 = _collect_zone_world_bounds(zone_root)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var sort_bounds: Rect2 = _collect_zone_world_bounds(zone_root, true)
	if sort_bounds.size.x <= 0.0 or sort_bounds.size.y <= 0.0:
		sort_bounds = bounds
	var sort_origin_y: float = sort_bounds.position.y + (sort_bounds.size.y * 0.5)
	var sort_factor: float = 1.0
	if sort_bounds.size.y > 1.0:
		sort_factor = min(1.0, 3000.0 / sort_bounds.size.y)
	Y_SORTING.configure_world_y_mapping(sort_origin_y, sort_factor)
	camera.limit_left = int(floor(bounds.position.x))
	camera.limit_top = int(floor(bounds.position.y))
	camera.limit_right = int(ceil(bounds.position.x + bounds.size.x))
	camera.limit_bottom = int(ceil(bounds.position.y + bounds.size.y))


func _collect_zone_world_bounds(zone_root: Node, only_y_sorted_layers: bool = false) -> Rect2:
	if zone_root == null:
		return Rect2()
	var has_bounds := false
	var min_pos := Vector2.ZERO
	var max_pos := Vector2.ZERO
	var stack: Array[Node] = [zone_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is TileMapLayer:
			var tile_layer := current as TileMapLayer
			if only_y_sorted_layers and not tile_layer.y_sort_enabled:
				for child in current.get_children():
					if child is Node:
						stack.append(child)
				continue
			var used: Rect2i = tile_layer.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				var start_local: Vector2 = tile_layer.map_to_local(used.position)
				var end_local: Vector2 = tile_layer.map_to_local(used.position + used.size)
				var top_left: Vector2 = tile_layer.to_global(start_local)
				var bottom_right: Vector2 = tile_layer.to_global(end_local)
				if not has_bounds:
					min_pos = Vector2(min(top_left.x, bottom_right.x), min(top_left.y, bottom_right.y))
					max_pos = Vector2(max(top_left.x, bottom_right.x), max(top_left.y, bottom_right.y))
					has_bounds = true
				else:
					min_pos.x = min(min_pos.x, top_left.x, bottom_right.x)
					min_pos.y = min(min_pos.y, top_left.y, bottom_right.y)
					max_pos.x = max(max_pos.x, top_left.x, bottom_right.x)
					max_pos.y = max(max_pos.y, top_left.y, bottom_right.y)
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	if not has_bounds:
		return Rect2()
	return Rect2(min_pos, max_pos - min_pos).grow(256.0)

func _resolve_spawn_marker(zone_root: Node, requested_spawn_name: String) -> Marker2D:
	if zone_root == null:
		return null

	# 1) Explicit spawn name from portal/flow.
	var requested: Node = zone_root.get_node_or_null(requested_spawn_name)
	if requested is Marker2D:
		return requested as Marker2D

	# 2) Conventional name used by existing zones.
	var default_spawn: Node = zone_root.get_node_or_null("SpawnPoint")
	if default_spawn is Marker2D:
		return default_spawn as Marker2D

	# 3) First-entry markers can act as normal fallback if no SpawnPoint exists.
	var first_entry_marker: Marker2D = _find_first_marker_with_script(zone_root, FIRST_ENTRY_SPAWN_POINT)
	if first_entry_marker != null:
		return first_entry_marker

	# 4) Last resort: any marker in the zone.
	return _find_first_marker_in_tree(zone_root)


func _find_first_marker_with_script(root: Node, script_ref: Script) -> Marker2D:
	if root == null or script_ref == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D and current.get_script() == script_ref:
			return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


func _find_first_marker_in_tree(root: Node) -> Marker2D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D:
			return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


# ---------------------------
# Target API
# ---------------------------
func set_target(mob: Node) -> void:
	if mob == null or not is_instance_valid(mob):
		current_target = null
		return
	current_target = mob


func get_target() -> Node:
	if current_target == null or not is_instance_valid(current_target):
		current_target = null
		return null

	# Сброс, если цель вне видимости камеры
	if current_target is Node2D:
		var t := current_target as Node2D
		if not _is_world_pos_visible(t.global_position):
			current_target = null
			return null

	return current_target


func clear_target() -> void:
	current_target = null


# ---------------------------
# Input: click/tap to select target
# ---------------------------
func _input(event: InputEvent) -> void:
	var screen_pos: Vector2
	var pressed: bool = false

	# Mouse click
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			if debug_world_probe_under_mouse:
				_debug_probe_under_mouse(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			screen_pos = mb.position
			pressed = true

	# Touch
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			screen_pos = st.position
			pressed = true

	if not pressed:
		return

	if debug_targeting_clicks:
		print("[TargetingDebug] click screen=", screen_pos)

	if _is_ui_press_event(screen_pos):
		if debug_targeting_clicks:
			var hit := _get_ui_control_at_screen_pos(screen_pos)
			var hit_name := "<null>"
			var hit_type := "<null>"
			if hit != null:
				hit_name = String((hit as Node).name)
				hit_type = hit.get_class()
			print("[TargetingDebug] blocked by UI control=", hit_name, " type=", hit_type)
		return


	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var mob: Node = _pick_mob_at_world_pos(world_pos)
	if debug_targeting_clicks:
		print("[TargetingDebug] world=", world_pos, " mob=", mob)

	if mob != null:
		set_target(mob)
		if debug_targeting_clicks:
			print("[TargetingDebug] set_target -> ", mob)
	else:
		clear_target()
		if debug_targeting_clicks:
			print("[TargetingDebug] clear_target (no mob under click)")


func _is_ui_press_event(screen_pos: Vector2) -> bool:
	var hit := _get_ui_control_at_screen_pos(screen_pos)
	if hit == null:
		return false

	var node: Control = hit
	while node != null:
		if node.visible and node.mouse_filter == Control.MOUSE_FILTER_STOP and _should_block_world_targeting(node):
			return true
		node = node.get_parent() as Control
	return false


func _should_block_world_targeting(c: Control) -> bool:
	if c == null:
		return false
	# Built-in interactive widgets.
	if _is_interactive_ui_control(c):
		return true
	# Custom scripted controls (e.g. mobile joystick/pads).
	if c.get_script() != null:
		return true
	# Labels/panels with explicitly connected gui_input handlers.
	if c.gui_input.get_connections().size() > 0:
		return true
	return false


func _get_ui_control_at_screen_pos(screen_pos: Vector2) -> Control:
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	# Prefer hover on desktop (cheap and reliable for mouse).
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered != null and hovered.get_global_rect().has_point(screen_pos):
		return hovered

	# Godot version in this project doesn't expose `gui_pick` on Window/Viewport,
	# so we resolve topmost control manually for touch/click position.
	var root: Node = get_tree().root
	if root == null:
		return null
	return _find_top_control_at_pos(root, screen_pos)


func _find_top_control_at_pos(node: Node, screen_pos: Vector2) -> Control:
	if node == null:
		return null

	if node is Control:
		var ctrl := node as Control
		if not ctrl.visible:
			return null
		if ctrl.clip_contents and not ctrl.get_global_rect().has_point(screen_pos):
			return null

	# Traverse children in reverse order to match draw/input priority.
	for i in range(node.get_child_count() - 1, -1, -1):
		var child: Node = node.get_child(i)
		var hit := _find_top_control_at_pos(child, screen_pos)
		if hit != null:
			return hit

	if node is Control:
		var ctrl2 := node as Control
		if ctrl2.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctrl2.get_global_rect().has_point(screen_pos):
			return ctrl2
	return null


func _is_interactive_ui_control(c: Control) -> bool:
	if c == null:
		return false
	# Реально кликабельные/вводные контролы.
	return (
		c is BaseButton
		or c is LineEdit
		or c is TextEdit
		or c is ItemList
		or c is Tree
		or c is OptionButton
		or c is SpinBox
		or c is Slider
		or c is ScrollBar
	)



func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	var cam := vp.get_camera_2d()
	if cam == null:
		return vp.get_canvas_transform().affine_inverse() * screen_pos
	if not use_cam_screen_center_for_world_math:
		return vp.get_canvas_transform().affine_inverse() * screen_pos
	var center_world := _get_world_screen_center(cam)
	var screen_size := vp.get_visible_rect().size
	var screen_center := screen_size * 0.5
	var delta_screen := screen_pos - screen_center
	var zoom := cam.zoom
	var delta_world := Vector2(delta_screen.x * zoom.x, delta_screen.y * zoom.y)
	return center_world + delta_world


func _pick_mob_at_world_pos(world_pos: Vector2) -> Node:
	var vp: Viewport = get_viewport()
	var space_state: PhysicsDirectSpaceState2D = vp.world_2d.direct_space_state

	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 0xFFFFFFFF

	var hits: Array[Dictionary] = space_state.intersect_point(params, 32)
	if hits.is_empty():
		return null

	for hit: Dictionary in hits:
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == null:
			continue

		var node: Node = collider_obj as Node
		while node != null:
			if node.is_in_group("mobs"):
				return node
			if allow_corpse_targeting and node is Corpse:
				return node
			node = node.get_parent()

	return null


func _debug_probe_under_mouse(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	print("[SortProbe] screen=", screen_pos, " world=", world_pos)
	if player != null and is_instance_valid(player):
		var p_z: int = int((player as CanvasItem).z_index) if player is CanvasItem else 0
		var root_y := float(player.global_position.y)
		var root_pos := player.global_position
		var anchor_global := root_pos
		if player.has_method("get_sort_anchor_global"):
			var anchor_v: Variant = player.call("get_sort_anchor_global")
			if anchor_v is Vector2:
				anchor_global = anchor_v as Vector2
		var wc_global := root_pos
		if player.has_method("get_world_collider_center_global"):
			var wc_v: Variant = player.call("get_world_collider_center_global")
			if wc_v is Vector2:
				wc_global = wc_v as Vector2
		var has_y_sort_origin := false
		var y_sort_origin_v: Variant = null
		var player_origin_info := _read_node_y_sort_origin_local(player)
		has_y_sort_origin = bool(player_origin_info.get("has_origin", false))
		y_sort_origin_v = player_origin_info.get("origin", 0.0)
		var origin_source := String(player_origin_info.get("source", "none"))
		var parent_path: String = str(player.get_parent().get_path()) if player.get_parent() != null else "<null>"
		var runtime_sort_y := root_y
		var runtime_parent_z := 0
		var runtime_parent_z_rel := true
		if player.get_parent() is Node2D and String((player.get_parent() as Node).name) == "__player_sort_pivot":
			var pivot_parent := player.get_parent() as Node2D
			runtime_sort_y = float(pivot_parent.global_position.y)
			runtime_parent_z = int((pivot_parent as CanvasItem).z_index) if pivot_parent is CanvasItem else 0
			runtime_parent_z_rel = (pivot_parent as CanvasItem).z_as_relative if pivot_parent is CanvasItem else true
		print("[SortProbe][Player] root_pos=", root_pos, " root_y=", root_y, " z=", p_z, " parent=", parent_path)
		print("[SortProbe][Player] anchor_global=", anchor_global, " anchor_y=", float(anchor_global.y), " wc_global=", wc_global, " wc_y=", float(wc_global.y))
		print("[SortProbe][Player] runtime_sort_y=", runtime_sort_y, " runtime_parent_z=", runtime_parent_z, " runtime_parent_z_rel=", runtime_parent_z_rel)
		if has_y_sort_origin:
			var computed_y := root_y + float(y_sort_origin_v)
			print("[SortProbe][Player] y_sort_origin(local)=", y_sort_origin_v, " source=", origin_source, " computed_global_y=", computed_y, " anchor_delta=", float(anchor_global.y) - computed_y)
		else:
			if origin_source == "meta":
				print("[SortProbe][Player] y_sort_origin(local)=<meta-only ", y_sort_origin_v, " renderer_uses_origin=false>")
			else:
				print("[SortProbe][Player] y_sort_origin(local)=<missing on Player node>")
	var y_map: Dictionary = Y_SORTING.get_world_y_mapping_debug()
	print("[SortProbe] y_map origin=", float(y_map.get("origin_y", 0.0)), " factor=", float(y_map.get("factor", 0.0)))

	var zone_root: Node = null
	if zone_container != null and zone_container.get_child_count() > 0:
		zone_root = zone_container.get_child(0)
	if zone_root == null:
		print("[SortProbe] no zone root in ZoneContainer")
		return

	var layers: Array[TileMapLayer] = []
	var stack: Array[Node] = [zone_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is TileMapLayer:
			layers.append(current as TileMapLayer)
		for child in current.get_children():
			if child is Node:
				stack.append(child)

	for layer in layers:
		var cell: Vector2i = layer.local_to_map(layer.to_local(world_pos))
		var source_id: int = layer.get_cell_source_id(cell)
		if source_id == -1:
			continue
		if layer.tile_set == null or not layer.tile_set.has_source(source_id):
			continue
		var tile_data := layer.get_cell_tile_data(cell)
		var tile_y_sort_origin := 0.0
		var tile_texture_origin_y := 0.0
		if tile_data != null and tile_data.has_method("get_y_sort_origin"):
			tile_y_sort_origin = float(tile_data.call("get_y_sort_origin"))
		if tile_data != null and tile_data.has_method("get_texture_origin"):
			var tex_origin_v: Variant = tile_data.call("get_texture_origin")
			if tex_origin_v is Vector2i:
				tile_texture_origin_y = float((tex_origin_v as Vector2i).y)
			elif tex_origin_v is Vector2:
				tile_texture_origin_y = float((tex_origin_v as Vector2).y)
		var tile_anchor_world := layer.to_global(layer.map_to_local(cell) + Vector2(0.0, tile_y_sort_origin))
		print("[SortProbe][Tile] layer=", layer.get_path(), " y_sort=", layer.y_sort_enabled, " z=", layer.z_index, " scale=", layer.scale, " cell=", cell, " source=", source_id, " texture_origin_y=", tile_texture_origin_y, " y_sort_origin=", tile_y_sort_origin, " anchor_y=", float(tile_anchor_world.y))

	var entities := get_tree().get_nodes_in_group("y_sort_entities")
	for e in entities:
		if not (e is Node2D):
			continue
		var n := e as Node2D
		if not is_instance_valid(n):
			continue
		if n.global_position.distance_to(world_pos) > 260.0:
			continue
		var ez: int = int((n as CanvasItem).z_index) if n is CanvasItem else 0
		var origin_info := _read_node_y_sort_origin_local(n)
		var has_origin := bool(origin_info.get("has_origin", false))
		var local_origin_y := float(origin_info.get("origin", 0.0))
		var origin_source := String(origin_info.get("source", "none"))
		var effective_sort_y := float(n.global_position.y) + local_origin_y if has_origin else float(n.global_position.y)
		var origin_print: String = str(local_origin_y) if has_origin else "<none>"
		if player != null and is_instance_valid(player) and n == player:
			var p_parent := n.get_parent()
			if p_parent is Node2D and String((p_parent as Node).name) == "__player_sort_pivot":
				effective_sort_y = float((p_parent as Node2D).global_position.y)
		if origin_source == "meta" and not has_origin:
			origin_print = "<meta-only %s>" % str(local_origin_y)
		print("[SortProbe][Entity] node=", n.get_path(), " root_y=", n.global_position.y, " sort_y=", effective_sort_y, " local_origin=", origin_print, " source=", origin_source, " z=", ez, " pos=", n.global_position)


func _is_world_pos_visible(world_pos: Vector2) -> bool:
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return true

	var center := _get_world_screen_center(cam)
	var half_size: Vector2 = vp.get_visible_rect().size * 0.5 * cam.zoom
	var rect := Rect2(center - half_size, half_size * 2.0)
	return rect.has_point(world_pos)


func get_nearest_graveyard_position(from_world_pos: Vector2) -> Vector2:
	var graveyards := get_tree().get_nodes_in_group("graveyards")

	var best_pos: Vector2 = from_world_pos
	var best_dist: float = INF

	for g in graveyards:
		if g == null:
			continue

		if g.has_method("get_spawn_position"):
			var p: Vector2 = g.call("get_spawn_position")
			var d: float = from_world_pos.distance_to(p)
			if d < best_dist:
				best_dist = d
				best_pos = p
		elif g is Node2D:
			var p2: Vector2 = (g as Node2D).global_position
			var d2: float = from_world_pos.distance_to(p2)
			if d2 < best_dist:
				best_dist = d2
				best_pos = p2

	return best_pos


# Preferred API: accept PackedScene directly (safer than string paths).
func load_zone_scene(zone_scene: PackedScene, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene == null:
		push_error("Zone scene is null.")
		return
	call_deferred("_load_zone_scene_deferred", zone_scene, spawn_name)


func _load_zone_scene_deferred(zone_scene: PackedScene, spawn_name: String) -> void:
	for child in zone_container.get_children():
		child.queue_free()

	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	var spawn: Node = new_zone.get_node_or_null(spawn_name)
	if spawn is Marker2D:
		player.global_position = (spawn as Marker2D).global_position
	else:
		var default_spawn: Node = new_zone.get_node_or_null("SpawnPoint")
		if default_spawn is Marker2D:
			player.global_position = (default_spawn as Marker2D).global_position
		else:
			player.global_position = new_zone.global_position

	clear_target()


func save_now() -> void:
	if has_method("_do_save_now"):
		call("_do_save_now")
		return
	if has_method("_flush_save"):
		call("_flush_save")
		return
	if has_method("request_save"):
		request_save("save_now")
