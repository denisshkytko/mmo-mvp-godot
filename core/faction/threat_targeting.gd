extends RefCounted
class_name ThreatTargeting

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const DANGER_COEFF := 1.0
const INFLUENCE_DIRECT := 1.0
const INFLUENCE_COMBAT := 0.75
const FACTION_UNITS_CACHE_REFRESH_SEC: float = 0.20

static var _cached_unit_ids: Array[int] = []
static var _cached_units_until_sec: float = 0.0

static func pick_target_by_threat(
	actor: Node2D,
	actor_faction_id: String,
	home_pos: Vector2,
	leash_distance: float,
	aggro_radius: float,
	direct_attackers: Dictionary,
	metric_prefix: String = ""
) -> Node2D:
	var t_total := Time.get_ticks_usec()
	if actor == null or not is_instance_valid(actor):
		_add_metric(metric_prefix, "threat_total", t_total)
		return null

	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var best_target: Node2D = null
	var best_threat: float = 0.0
	var leash_distance_sq: float = leash_distance * leash_distance
	var aggro_radius_sq: float = aggro_radius * aggro_radius
	var actor_pos: Vector2 = actor.global_position

	var t_direct := Time.get_ticks_usec()
	for attacker_id in direct_attackers.keys():
		var attacker_obj: Object = instance_from_id(int(attacker_id))
		if attacker_obj == null or not is_instance_valid(attacker_obj):
			continue
		if not (attacker_obj is Node2D):
			continue
		var candidate := attacker_obj as Node2D
		if candidate == null or not is_instance_valid(candidate):
			continue
		if "is_dead" in candidate and bool(candidate.get("is_dead")):
			continue

		var tf: String = ""
		if candidate.has_method("get_faction_id"):
			tf = String(candidate.call("get_faction_id"))
		var rel := FactionRules.relation(actor_faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue

		if home_pos.distance_squared_to(candidate.global_position) > leash_distance_sq:
			continue

		var dps := _get_dps(candidate, now_sec)
		var threat := dps * DANGER_COEFF * INFLUENCE_DIRECT
		if threat > best_threat:
			best_threat = threat
			best_target = candidate
	_add_metric(metric_prefix, "threat_direct_scan", t_direct)
	FRAME_PROFILER.add_count("%s.targeting.direct_attackers_checked" % _metric_root(metric_prefix), float(direct_attackers.size()))

	var t_faction_scan := Time.get_ticks_usec()
	var unit_ids := _get_cached_faction_unit_ids(actor.get_tree(), now_sec)
	var scanned_units: int = 0
	for unit_id in unit_ids:
		scanned_units += 1
		var obj := instance_from_id(unit_id)
		if obj == null or not is_instance_valid(obj):
			continue
		if obj == actor:
			continue
		if not (obj is Node2D):
			continue
		var candidate := obj as Node2D
		if "is_dead" in candidate and bool(candidate.get("is_dead")):
			continue
		if home_pos.distance_squared_to(candidate.global_position) > leash_distance_sq:
			continue
		if actor_pos.distance_squared_to(candidate.global_position) > aggro_radius_sq:
			continue

		var tf: String = ""
		if candidate.has_method("get_faction_id"):
			tf = String(candidate.call("get_faction_id"))
		var rel := FactionRules.relation(actor_faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue
		if not candidate.has_method("is_in_combat"):
			continue
		if not bool(candidate.call("is_in_combat")):
			continue

		var dps := _get_dps(candidate, now_sec)
		var threat := dps * DANGER_COEFF * INFLUENCE_COMBAT
		if threat > best_threat:
			best_threat = threat
			best_target = candidate
	_add_metric(metric_prefix, "threat_faction_scan", t_faction_scan)
	FRAME_PROFILER.add_count("%s.targeting.faction_units_checked" % _metric_root(metric_prefix), float(scanned_units))

	if best_threat > 0.0:
		_add_metric(metric_prefix, "threat_total", t_total)
		return best_target
	_add_metric(metric_prefix, "threat_total", t_total)
	return null


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

static func _get_dps(candidate: Node, now_sec: float) -> float:
	if candidate == null:
		return 0.0
	var danger_meter := _get_danger_meter(candidate)
	if danger_meter == null:
		return 0.0
	return float(danger_meter.get_dps(now_sec))

static func _get_danger_meter(candidate: Node) -> DangerMeterComponent:
	if candidate == null:
		return null
	if candidate.has_method("get_danger_meter"):
		var meter = candidate.call("get_danger_meter")
		if meter is DangerMeterComponent:
			return meter
	if "c_danger" in candidate:
		var meter = candidate.c_danger
		if meter is DangerMeterComponent:
			return meter
	var node := candidate.get_node_or_null("Components/Danger")
	if node is DangerMeterComponent:
		return node
	return null
