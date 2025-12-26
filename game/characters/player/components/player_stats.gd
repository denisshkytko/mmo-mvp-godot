extends Node
class_name PlayerStats

var p: Player = null

func setup(player: Player) -> void:
	p = player

func add_xp(amount: int) -> void:
	if p == null:
		return
	if amount <= 0:
		return

	p.xp += amount
	while p.xp >= p.xp_to_next:
		p.xp -= p.xp_to_next
		p.level += 1
		p.xp_to_next = _calc_xp_to_next(p.level)
		recalculate_for_level(true)

func _calc_xp_to_next(new_level: int) -> int:
	return 10 + (new_level - 1) * 5

func recalculate_for_level(full_restore: bool) -> void:
	if p == null:
		return

	p.max_hp = 100 + (p.level - 1) * 15
	p.attack = 10 + (p.level - 1) * 3
	p.defense = 2 + (p.level - 1) * 1

	p.max_mana = 60 + (p.level - 1) * 8

	if full_restore:
		p.current_hp = p.max_hp
		p.mana = p.max_mana
	else:
		p.current_hp = clamp(p.current_hp, 0, p.max_hp)
		p.mana = clamp(p.mana, 0, p.max_mana)

func take_damage(raw_damage: int) -> void:
	if p == null:
		return

	# неуязвимость через баф (если есть)
	var buffs: PlayerBuffs = p.c_buffs
	if buffs != null and buffs.is_invulnerable():
		return

	var dmg: int = max(1, raw_damage - p.defense)
	p.current_hp = max(0, p.current_hp - dmg)

	if p.current_hp <= 0:
		_on_death()

func _on_death() -> void:
	# 1) помечаем игрока мёртвым (останавливаем движение/атаки)
	p.is_dead = true

	# 2) показываем окно респавна (RespawnUi в GameUI)
	var respawn_ui: Node = get_tree().get_first_node_in_group("respawn_ui")
	if respawn_ui != null and respawn_ui.has_method("open"):
		respawn_ui.call("open", p, 3.0) # 3 секунды ожидания (можешь поменять)
