extends RefCounted
class_name CombatReset

const LootRights := preload("res://core/loot/loot_rights.gd")

# ------------------------------------------------------------
# CombatReset
#
# Мини-helper для общих действий при "сбросе боя":
# - сброс прав на лут
# - включение регена
# - reset_combat у компонента
#
# Специфичные поля (aggressor/current_target/velocity) остаются
# в сущностях.
# ------------------------------------------------------------

static func reset_common(unit: Node, combat_component: Node, set_regen_active: Callable, set_loot_owner: Callable) -> void:
	# Этот helper специально сделан простым и безопасным.
	# Мы не лезем в конкретные поля, а работаем через callables.
	set_loot_owner.call(LootRights.clear_owner())
	set_regen_active.call(true)
	if combat_component != null and is_instance_valid(combat_component) and combat_component.has_method("reset_combat"):
		combat_component.call("reset_combat")
