extends RefCounted
class_name YSorting

# Legacy helper retained only for world-y mapping debug/probes.
# Local overlap z-index boosting is intentionally removed.

const WORLD_Y_TO_Z_FACTOR: float = 1.0

static var _world_y_origin: float = 0.0
static var _world_y_to_z_factor: float = WORLD_Y_TO_Z_FACTOR


static func z_index_for_local_overlap(_owner: Node2D, default_z: int = 0) -> int:
	return default_z


static func configure_world_y_mapping(origin_y: float, factor: float = WORLD_Y_TO_Z_FACTOR) -> void:
	_world_y_origin = origin_y
	_world_y_to_z_factor = clampf(factor, 0.0001, 10.0)


static func get_world_y_mapping_debug() -> Dictionary:
	return {
		"origin_y": _world_y_origin,
		"factor": _world_y_to_z_factor,
	}


static func refresh_local_overlap_around(_owner: Node2D, _default_z: int = 0) -> void:
	return
