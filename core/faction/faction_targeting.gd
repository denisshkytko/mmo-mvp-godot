extends RefCounted
class_name FactionTargeting
const FACTION_UNITS_CACHE_REFRESH_SEC: float = 0.20

static var _cached_units: Array = []
static var _cached_units_until_sec: float = 0.0

# ------------------------------------------------------------
# FactionTargeting
#
# Базовый поиск враждебной цели среди "faction_units".
# Используется NAM и FactionNPC (без их специфики).
# ------------------------------------------------------------

static func pick_hostile_target(self_node: Node2D, self_faction_id: String, radius: float) -> Node2D:
	if self_node == null or not is_instance_valid(self_node):
		return null

	var best: Node2D = null
	var best_d: float = INF
	var radius_sq: float = radius * radius
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0

	var units := _get_cached_faction_units(self_node.get_tree(), now_sec)
	for u in units:
		if u == self_node:
			continue
		if not (u is Node2D):
			continue
		var n := u as Node2D
		if not is_instance_valid(n):
			continue
		if "is_dead" in n and bool(n.get("is_dead")):
			continue

		var tf: String = ""
		if n.has_method("get_faction_id"):
			tf = String(n.call("get_faction_id"))
		var rel := FactionRules.relation(self_faction_id, tf)
		if rel != FactionRules.Relation.HOSTILE:
			continue

		var d_sq := self_node.global_position.distance_squared_to(n.global_position)
		if d_sq <= radius_sq and d_sq < best_d:
			best_d = d_sq
			best = n

	return best


static func _get_cached_faction_units(tree: SceneTree, now_sec: float) -> Array:
	if tree == null:
		return []
	if now_sec >= _cached_units_until_sec:
		_cached_units = tree.get_nodes_in_group("faction_units")
		_cached_units_until_sec = now_sec + FACTION_UNITS_CACHE_REFRESH_SEC
	return _cached_units
