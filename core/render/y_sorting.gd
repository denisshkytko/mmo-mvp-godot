extends RefCounted
class_name YSorting

const OVERLAP_X_THRESHOLD: float = 120.0
const OVERLAP_Y_DOWN_THRESHOLD: float = 120.0
const Y_DEADZONE: float = 6.0
const IDLE_RECHECK_INTERVAL_MSEC: int = 250
const MOVEMENT_EPSILON: float = 1.5
const ACTIVE_KEEPALIVE_MSEC: int = 450
const BASE_WORLD_Z_LAYER: int = 50
const WORLD_Y_TO_Z_FACTOR: float = 1.0
const WORLD_Y_TO_Z_CLAMP_MIN: int = -2000000
const WORLD_Y_TO_Z_CLAMP_MAX: int = 2000000

static var _state_by_owner_id: Dictionary = {}

# Keeps a shared base layer for all actors and changes order only when they are
# visually close/overlapping. This prevents huge per-entity z-index spread.
static func z_index_for_local_overlap(owner: Node2D, default_z: int = 0) -> int:
	if owner == null or not is_instance_valid(owner):
		return default_z
	var tree := owner.get_tree()
	if tree == null:
		return default_z

	var owner_id := owner.get_instance_id()
	var now_msec := Time.get_ticks_msec()
	var self_anchor := _resolve_sort_anchor(owner)
	var state := _state_by_owner_id.get(owner_id, {
		"last_anchor": self_anchor,
		"last_check_msec": 0,
		"last_z": default_z,
		"active_until_msec": 0
	}) as Dictionary

	var last_anchor: Vector2 = state.get("last_anchor", self_anchor) as Vector2
	var last_check_msec: int = int(state.get("last_check_msec", 0))
	var last_z: int = int(state.get("last_z", default_z))
	var active_until_msec: int = int(state.get("active_until_msec", 0))

	var moved := self_anchor.distance_to(last_anchor) > MOVEMENT_EPSILON
	var still_active := now_msec < active_until_msec
	var idle_recheck_due := (now_msec - last_check_msec) >= IDLE_RECHECK_INTERVAL_MSEC

	if not moved and not still_active and not idle_recheck_due:
		return last_z

	_cleanup_stale_state_if_needed(tree)

	var relative: int = 0
	var has_close_neighbors: bool = false

	for n in _get_sort_candidates(tree):
		if not (n is Node2D):
			continue
		var other := n as Node2D
		if other == owner or not is_instance_valid(other):
			continue
		if "is_dead" in other and bool(other.get("is_dead")):
			continue

		var other_anchor := _resolve_sort_anchor(other)
		var dx: float = absf(self_anchor.x - other_anchor.x)
		var dy: float = self_anchor.y - other_anchor.y
		# We only care about actors above the owner (dy > 0), because only then
		# this owner should be lifted in front.
		if dy <= Y_DEADZONE:
			continue
		if dx > OVERLAP_X_THRESHOLD or dy > OVERLAP_Y_DOWN_THRESHOLD:
			continue
		has_close_neighbors = true

		# Never push actor below base z-layer (can visually fall under ground/tile layer).
		# Increase local z-index by overlap rank for stronger ordering with multiple
		# simultaneously intersecting actors.
		relative += 1

	var world_y_base: int = _world_y_base_z(self_anchor.y)
	var base_z: int = BASE_WORLD_Z_LAYER + default_z + world_y_base
	var resolved_z: int = base_z if relative <= 0 else base_z + relative
	state["last_anchor"] = self_anchor
	state["last_check_msec"] = now_msec
	state["last_z"] = resolved_z
	state["active_until_msec"] = now_msec + ACTIVE_KEEPALIVE_MSEC if has_close_neighbors else now_msec
	_state_by_owner_id[owner_id] = state
	return resolved_z

static func _world_y_base_z(world_y: float) -> int:
	var scaled := int(floor(world_y * WORLD_Y_TO_Z_FACTOR))
	return clampi(scaled, WORLD_Y_TO_Z_CLAMP_MIN, WORLD_Y_TO_Z_CLAMP_MAX)

static func _get_sort_candidates(tree: SceneTree) -> Array:
	var preferred := tree.get_nodes_in_group("y_sort_entities")
	if not preferred.is_empty():
		return preferred
	return tree.get_nodes_in_group("faction_units")

static func _cleanup_stale_state_if_needed(tree: SceneTree) -> void:
	if _state_by_owner_id.size() <= 128:
		return
	var valid_ids := {}
	for n in _get_sort_candidates(tree):
		if n is Node:
			valid_ids[(n as Node).get_instance_id()] = true
	for key in _state_by_owner_id.keys():
		if not valid_ids.has(int(key)):
			_state_by_owner_id.erase(key)

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

static func refresh_local_overlap_around(owner: Node2D, default_z: int = 0) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var tree := owner.get_tree()
	if tree == null:
		return

	# Refresh owner first so newly spawned/appeared entities are correctly placed.
	z_index_for_local_overlap(owner, default_z)

	var self_anchor := _resolve_sort_anchor(owner)
	for n in _get_sort_candidates(tree):
		if not (n is Node2D):
			continue
		var other := n as Node2D
		if other == owner or not is_instance_valid(other):
			continue
		if not other.has_method("refresh_local_overlap_sorting"):
			continue
		var other_anchor := _resolve_sort_anchor(other)
		var dx: float = absf(self_anchor.x - other_anchor.x)
		var dy: float = absf(self_anchor.y - other_anchor.y)
		if dx > OVERLAP_X_THRESHOLD or dy > OVERLAP_Y_DOWN_THRESHOLD:
			continue
		other.call("refresh_local_overlap_sorting")
