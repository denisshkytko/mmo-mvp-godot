extends RefCounted
class_name FactionTargeting

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const FACTION_UNITS_CACHE_REFRESH_SEC: float = 0.20

static var _cached_unit_ids: Array[int] = []
static var _cached_units_until_sec: float = 0.0

# ------------------------------------------------------------
# FactionTargeting
#
# Базовый поиск враждебной цели среди "faction_units".
# Используется NAM и FactionNPC (без их специфики).
# ------------------------------------------------------------

static func pick_hostile_target(self_node: Node2D, self_faction_id: String, radius: float, metric_prefix: String = "") -> Node2D:
	var t_total := Time.get_ticks_usec()
	if self_node == null or not is_instance_valid(self_node):
		_add_metric(metric_prefix, "faction_pick_total", t_total)
		return null

	var best: Node2D = null
	var best_d: float = INF
	var radius_sq: float = radius * radius
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var self_pos: Vector2 = self_node.global_position

	var nearby_units := _get_nearby_faction_units(self_node, radius, now_sec)
	var scanned_units: int = 0
	for n in nearby_units:
		scanned_units += 1
		if n == null or not is_instance_valid(n):
			continue
		if "is_dead" in n and bool(n.get("is_dead")):
			continue

		var d_sq := self_pos.distance_squared_to(n.global_position)
		if d_sq <= radius_sq and d_sq < best_d:
			var tf: String = ""
			if n.has_method("get_faction_id"):
				tf = String(n.call("get_faction_id"))
			var rel := FactionRules.relation(self_faction_id, tf)
			if rel != FactionRules.Relation.HOSTILE:
				continue
			best_d = d_sq
			best = n
	FRAME_PROFILER.add_count("%s.targeting.faction_pick_units_checked" % _metric_root(metric_prefix), float(scanned_units))
	_add_metric(metric_prefix, "faction_pick_total", t_total)
	return best

static func _get_nearby_faction_units(self_node: Node2D, radius: float, now_sec: float) -> Array[Node2D]:
	if self_node == null or not is_instance_valid(self_node):
		return []
	var tree := self_node.get_tree()
	if tree == null or tree.root == null:
		return _resolve_units_from_ids(_get_cached_faction_unit_ids(tree, now_sec))
	var cache := tree.root.get_node_or_null("MobProximityCache")
	if cache != null and cache.has_method("get_nearby_faction_units"):
		var nearby_v: Variant = cache.call("get_nearby_faction_units", self_node, radius, "faction_units")
		if nearby_v is Array:
			var nearby_arr := nearby_v as Array
			var typed: Array[Node2D] = []
			for item in nearby_arr:
				if item is Node2D:
					typed.append(item as Node2D)
			return typed
	return _resolve_units_from_ids(_get_cached_faction_unit_ids(tree, now_sec))

static func _resolve_units_from_ids(unit_ids: Array[int]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for unit_id in unit_ids:
		var obj := instance_from_id(unit_id)
		if obj == null or not is_instance_valid(obj):
			continue
		if obj is Node2D:
			out.append(obj as Node2D)
	return out


static func _get_cached_faction_unit_ids(tree: SceneTree, now_sec: float) -> Array[int]:
	if tree == null:
		return []
	if now_sec >= _cached_units_until_sec:
		var raw := tree.get_nodes_in_group("faction_units")
		var sanitized: Array[int] = []
		for item in raw:
			var obj := item as Object
			if obj == null or not is_instance_valid(obj):
				continue
			sanitized.append(obj.get_instance_id())
		_cached_unit_ids = sanitized
		_cached_units_until_sec = now_sec + FACTION_UNITS_CACHE_REFRESH_SEC
	return _cached_unit_ids

static func _metric_root(metric_prefix: String) -> String:
	if metric_prefix.strip_edges() == "":
		return "targeting.physics"
	return metric_prefix

static func _add_metric(metric_prefix: String, suffix: String, started_usec: int) -> void:
	FRAME_PROFILER.add_usec("%s.%s" % [_metric_root(metric_prefix), suffix], Time.get_ticks_usec() - started_usec)
