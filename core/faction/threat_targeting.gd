extends RefCounted
class_name ThreatTargeting

const DANGER_COEFF := 1.0
const INFLUENCE_DIRECT := 1.0
const INFLUENCE_COMBAT := 0.75

static func pick_target_by_threat(
	actor: Node2D,
	actor_faction_id: String,
	home_pos: Vector2,
	leash_distance: float,
	aggro_radius: float,
	direct_attackers: Dictionary
) -> Node2D:
	if actor == null or not is_instance_valid(actor):
		return null

	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var best_target: Node2D = null
	var best_threat: float = 0.0

	for attacker_id in direct_attackers.keys():
		var attacker_obj: Object = instance_from_id(int(attacker_id))
		if attacker_obj == null or not (attacker_obj is Node2D):
			continue
		var candidate := attacker_obj as Node2D
		if not is_instance_valid(candidate):
			continue
		if "is_dead" in candidate and bool(candidate.get("is_dead")):
			continue

		var tf: String = ""
		if candidate.has_method("get_faction_id"):
			tf = String(candidate.call("get_faction_id"))
		var rel := FactionRules.relation(actor_faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue

		if candidate.global_position.distance_to(home_pos) > leash_distance:
			continue

		var dps := _get_dps(candidate, now_sec)
		var threat := dps * DANGER_COEFF * INFLUENCE_DIRECT
		if threat > best_threat:
			best_threat = threat
			best_target = candidate

	var units := actor.get_tree().get_nodes_in_group("faction_units")
	for u in units:
		if u == actor:
			continue
		if not (u is Node2D):
			continue
		var candidate := u as Node2D
		if not is_instance_valid(candidate):
			continue
		if "is_dead" in candidate and bool(candidate.get("is_dead")):
			continue
		if not candidate.has_method("is_in_combat"):
			continue
		if not bool(candidate.call("is_in_combat")):
			continue

		var tf: String = ""
		if candidate.has_method("get_faction_id"):
			tf = String(candidate.call("get_faction_id"))
		var rel := FactionRules.relation(actor_faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue

		if actor.global_position.distance_to(candidate.global_position) > aggro_radius:
			continue
		if candidate.global_position.distance_to(home_pos) > leash_distance:
			continue

		var dps := _get_dps(candidate, now_sec)
		var threat := dps * DANGER_COEFF * INFLUENCE_COMBAT
		if threat > best_threat:
			best_threat = threat
			best_target = candidate

	if best_threat > 0.0:
		return best_target
	return null

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
