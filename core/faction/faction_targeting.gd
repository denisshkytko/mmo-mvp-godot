extends RefCounted
class_name FactionTargeting

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

	var units := self_node.get_tree().get_nodes_in_group("faction_units")
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

		var d := self_node.global_position.distance_to(n.global_position)
		if d <= radius and d < best_d:
			best_d = d
			best = n

	return best
