extends RefCounted
class_name YSorting

const OVERLAP_X_THRESHOLD: float = 120.0
const OVERLAP_Y_THRESHOLD: float = 80.0
const Y_DEADZONE: float = 6.0

# Keeps a shared base layer for all actors and changes order only when they are
# visually close/overlapping. This prevents huge per-entity z-index spread.
static func z_index_for_local_overlap(owner: Node2D, default_z: int = 0) -> int:
	if owner == null or not is_instance_valid(owner):
		return default_z
	var tree := owner.get_tree()
	if tree == null:
		return default_z

	var self_anchor := _resolve_sort_anchor(owner)
	var has_overlap := false
	var relative := 0
	var seen_ids := {}

	for n in tree.get_nodes_in_group("faction_units"):
		if not (n is Node2D):
			continue
		var other := n as Node2D
		if other == owner or not is_instance_valid(other):
			continue
		var oid := other.get_instance_id()
		if seen_ids.has(oid):
			continue
		seen_ids[oid] = true
		if "is_dead" in other and bool(other.get("is_dead")):
			continue

		var other_anchor := _resolve_sort_anchor(other)
		var dx := abs(self_anchor.x - other_anchor.x)
		var dy := self_anchor.y - other_anchor.y
		if dx > OVERLAP_X_THRESHOLD or abs(dy) > OVERLAP_Y_THRESHOLD:
			continue

		has_overlap = true
		if dy > Y_DEADZONE:
			relative = max(relative, 1)
		elif dy < -Y_DEADZONE:
			relative = min(relative, -1)

	if not has_overlap:
		return default_z
	return default_z + relative

static func _resolve_sort_anchor(actor: Node2D) -> Vector2:
	if actor == null:
		return Vector2.ZERO
	if actor.has_method("get_sort_anchor_global"):
		var a: Variant = actor.call("get_sort_anchor_global")
		if a is Vector2:
			return a as Vector2
	if actor.has_method("get_body_hitbox_center_global"):
		var v: Variant = actor.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return actor.global_position
