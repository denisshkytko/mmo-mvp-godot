extends RefCounted
class_name YSorting

# Computes stable draw order for top-down actors.
# Higher Y (lower on screen) should be drawn in front.
static func z_index_from_world_collider(owner: Node2D, world_collision: CollisionShape2D) -> int:
	if owner == null or not is_instance_valid(owner):
		return 0
	if world_collision != null and is_instance_valid(world_collision):
		return int(round(world_collision.global_position.y))
	return int(round(owner.global_position.y))
