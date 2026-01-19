extends CanvasLayer

@onready var panel: Panel = $Root/SafeArea/Content/TargetPanel
@onready var name_label: Label = $Root/SafeArea/Content/TargetPanel/NameLabel
@onready var hp_fill: ColorRect = $Root/SafeArea/Content/TargetPanel/HpFill
@onready var hp_text: Label = $Root/SafeArea/Content/TargetPanel/HpText
@onready var hp_back: ColorRect = $Root/SafeArea/Content/TargetPanel/HpBack

# добавленный фон (см. шаг 1)
@onready var relation_bg: ColorRect = $Root/SafeArea/Content/TargetPanel/RelationBg

var _gm: Node = null
var _player: Node = null
var _target: Node = null
var _full_width: float = 0.0

func _ready() -> void:
	panel.visible = false
	_gm = get_tree().get_first_node_in_group("game_manager")
	_player = get_tree().get_first_node_in_group("player")

	# дождёмся 1 кадра, чтобы размеры UI были рассчитаны
	await get_tree().process_frame
	_full_width = hp_back.size.x
	hp_fill.size.x = _full_width
	hp_text.text = ""

func _process(_delta: float) -> void:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
		if _gm == null:
			panel.visible = false
			return

	var t: Node = _gm.call("get_target") if _gm.has_method("get_target") else null
	if t == null or not is_instance_valid(t):
		_target = null
		panel.visible = false
		return

	# target changed
	if t != _target:
		_target = t
		panel.visible = true
		_update_name()
		_update_relation_color()

	# HP обновляем каждый кадр (надёжно для прототипа)
	_update_hp()

func _update_name() -> void:
	if _target == null:
		name_label.text = ""
		return

	var display_name: String = ""

	if _target.has_method("get_display_name"):
		display_name = String(_target.call("get_display_name"))
	else:
		# 1) aggressive mob
		if _target is NormalAggresiveMob:
			var mob_id_val: Variant = _target.get("mob_id")
			if mob_id_val != null and String(mob_id_val) != "":
				display_name = String(mob_id_val)
			else:
				display_name = String(_target.name)

		# 2) neutral mob
		elif _target is NormalNeutralMob:
			var skin_val: Variant = _target.get("skin_id")
			if skin_val != null and String(skin_val) != "":
				display_name = String(skin_val)
			else:
				display_name = String(_target.name)

		# 3) faction npc
		elif _target is FactionNPC:
			var fid: String = ""
			if _target.has_method("get_faction_id"):
				fid = String(_target.call("get_faction_id"))

			var ft_val: Variant = _target.get("fighter_type")
			var ft: int = 0
			if ft_val != null:
				ft = int(ft_val)

			var ft_name: String = "NPC"
			if ft == 0:
				ft_name = "Civilian"
			elif ft == 1:
				ft_name = "Fighter"
			elif ft == 2:
				ft_name = "Mage"

			display_name = ("%s %s" % [fid, ft_name]).strip_edges()

		else:
			display_name = String(_target.name)

	# level suffix
	var lvl: int = 0
	if _target.has_method("get_level"):
		lvl = int(_target.call("get_level"))
	else:
		var ml: Variant = _target.get("mob_level")
		if ml != null:
			lvl = int(ml)
		else:
			var nl: Variant = _target.get("npc_level")
			if nl != null:
				lvl = int(nl)

	if lvl > 0:
		name_label.text = display_name + (" (lv %d)" % lvl)
	else:
		name_label.text = display_name


func _get_stats_node() -> Node:
	if _target == null:
		return null
	# стандарт у твоих мобов/нпс сейчас: Components/Stats
	if _target.has_node("Components/Stats"):
		var n: Node = _target.get_node("Components/Stats")
		return n
	return null

func _update_hp() -> void:
	if _target == null:
		hp_text.text = ""
		hp_fill.size.x = _full_width
		return

	var cur: int = -1
	var mx: int = -1

	# 1) через методы (если есть)
	if _target.has_method("get_current_hp") and _target.has_method("get_max_hp"):
		cur = int(_target.call("get_current_hp"))
		mx = int(_target.call("get_max_hp"))
	else:
		# 2) через Stats компонент
		var stats: Node = _get_stats_node()
		if stats != null:
			var cur_v: Variant = stats.get("current_hp")
			var mx_v: Variant = stats.get("max_hp")
			if cur_v != null and mx_v != null:
				cur = int(cur_v)
				mx = int(mx_v)
		else:
			# 3) запасной вариант — прямые поля
			var cur_val: Variant = _target.get("current_hp")
			var mx_val: Variant = _target.get("max_hp")
			if cur_val != null and mx_val != null:
				cur = int(cur_val)
				mx = int(mx_val)

	if cur < 0 or mx <= 0:
		hp_text.text = ""
		hp_fill.size.x = _full_width
		return

	mx = max(1, mx)
	cur = clamp(cur, 0, mx)

	hp_text.text = "%d/%d" % [cur, mx]
	var ratio: float = clamp(float(cur) / float(mx), 0.0, 1.0)
	hp_fill.size.x = _full_width * ratio

func _update_relation_color() -> void:
	if relation_bg == null:
		return

	var player_faction: String = "blue"
	if _player != null and is_instance_valid(_player) and _player.has_method("get_faction_id"):
		player_faction = String(_player.call("get_faction_id"))

	var target_faction: String = ""
	if _target != null and is_instance_valid(_target):
		if _target.has_method("get_faction_id"):
			target_faction = String(_target.call("get_faction_id"))
		else:
			# мобов определяем по классу
			if _target is NormalAggresiveMob:
				target_faction = "aggressive_mob"
			elif _target is NormalNeutralMob:
				target_faction = "neutral_mob"

	var rel: int = FactionRules.relation(player_faction, target_faction)

	# FRIENDLY -> green, NEUTRAL -> yellow, HOSTILE -> red
	if rel == FactionRules.Relation.FRIENDLY:
		relation_bg.color = Color(0.15, 0.55, 0.15, 0.55)
	elif rel == FactionRules.Relation.HOSTILE:
		relation_bg.color = Color(0.65, 0.15, 0.15, 0.55)
	else:
		relation_bg.color = Color(0.65, 0.55, 0.15, 0.55)
