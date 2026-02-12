extends CharacterBody2D
class_name Player

## NodeCache is a global helper (class_name). Avoid shadowing.
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const PROG := preload("res://core/stats/progression.gd")

@export var move_speed: float = MOVE_SPEED.PLAYER_BASE

# Auto-attack
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 0.8

# Combat state (used for HP regen rule: HP regenerates only out of combat)
var _targeters := {} # instance_id -> true

func on_targeted_by(attacker: Node) -> void:
	if attacker == null:
		return
	_targeters[attacker.get_instance_id()] = true

func on_untargeted_by(attacker: Node) -> void:
	if attacker == null:
		return
	_targeters.erase(attacker.get_instance_id())

func is_in_combat() -> bool:
	return _targeters.size() > 0

func is_out_of_combat() -> bool:
	return _targeters.size() == 0

# Primary stats are tuned per-character on the Player node (as you requested).
# Internally they are applied to the PlayerStats component.
@export_group("Primary Stats (Level 1)")
@export var base_str: int = 10
@export var base_agi: int = 10
@export var base_end: int = 10
@export var base_int: int = 10
@export var base_per: int = 10

@export_group("Primary Growth (Per Level)")
@export var str_per_level: int = 1
@export var agi_per_level: int = 1
@export var end_per_level: int = 1
@export var int_per_level: int = 1
@export var per_per_level: int = 1

var faction_id: String = "blue"
var class_id: String = "warrior"
var _starter_grant_waiting_for_db: bool = false

# Mobile input
var mobile_move_dir: Vector2 = Vector2.ZERO

# --- Public “state” fields (HUD/UI читает их напрямую) ---
var inventory: Inventory = null

var level: int = 1
var xp: int = 0
var xp_to_next: int = 10

var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 2

var max_mana: int = 60
var mana: int = 60

var is_dead: bool = false

# --- Consumables (food / drink / potion) ---
var _consumable_cd_end_sec: Dictionary = {} # kind -> float end time

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func is_consumable_on_cooldown(kind: String) -> bool:
	if kind == "":
		return false
	if not _consumable_cd_end_sec.has(kind):
		return false
	return _now_sec() < float(_consumable_cd_end_sec.get(kind, 0.0))

func start_consumable_cooldown(kind: String, seconds: float) -> void:
	if kind == "" or seconds <= 0.0:
		return
	_consumable_cd_end_sec[kind] = _now_sec() + seconds

func try_apply_consumable(item_id: String) -> Dictionary:
	# Applies the consumable's effect (instant or over-time) WITHOUT removing the item from inventory.
	# Returns {"ok": bool, "reason": String, "kind": String}
	if item_id == "" or is_dead:
		return {"ok": false, "reason": "invalid", "kind": ""}
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return {"ok": false, "reason": "no_db", "kind": ""}
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	var typ: String = String(meta.get("type", "")).to_lower()
	if typ != "food" and typ != "drink" and typ != "potion":
		return {"ok": false, "reason": "not_consumable", "kind": ""}
	# Required level gate (for usable items).
	var req_lvl: int = int(meta.get("required_level", 1))
	if req_lvl > level:
		return {"ok": false, "reason": "level", "kind": "" , "required_level": req_lvl}
	var cons: Dictionary = meta.get("consumable", {}) as Dictionary
	var kind: String = String(cons.get("kind", typ)).to_lower()
	if is_consumable_on_cooldown(kind):
		return {"ok": false, "reason": "cooldown", "kind": kind}

	# Potions use keys hp/mp, while food/drink use hp_total/mp_total.
	var hp_total: int = int(cons.get("hp_total", cons.get("hp", 0)))
	var mp_total: int = int(cons.get("mp_total", cons.get("mp", 0)))
	var instant: bool = bool(cons.get("instant", false))
	var duration_sec: float = float(cons.get("duration_sec", 0.0))

	# Determine if anything can be applied.
	var hp_need: int = max(0, max_hp - current_hp)
	var mp_need: int = max(0, max_mana - mana)
	var can_hp: bool = hp_total > 0 and hp_need > 0
	var can_mp: bool = mp_total > 0 and mp_need > 0
	if not can_hp and not can_mp:
		# Show which resource is full (best-effort).
		var r := "full"
		if hp_total > 0 and mp_total > 0:
			r = "hpmp_full"
		elif hp_total > 0:
			r = "hp_full"
		elif mp_total > 0:
			r = "mp_full"
		return {"ok": false, "reason": r, "kind": kind}

	# Apply effect
	if instant or duration_sec <= 0.0:
		if can_hp:
			var add_hp: int = min(hp_total, hp_need)
			current_hp = min(max_hp, current_hp + add_hp)
		if can_mp:
			var add_mp: int = min(mp_total, mp_need)
			mana = min(max_mana, mana + add_mp)
		# Cooldown
		start_consumable_cooldown(kind, 5.0 if typ == "potion" else 10.0)
		return {"ok": true, "reason": "", "kind": kind}

	# Over-time: heal/restore once per second, capped by total.
	var hp_per_sec: int = 0
	var mp_per_sec: int = 0
	if hp_total > 0:
		hp_per_sec = int(ceil(float(hp_total) / max(1.0, duration_sec)))
	if mp_total > 0:
		mp_per_sec = int(ceil(float(mp_total) / max(1.0, duration_sec)))
	# Unique id so multiple consumables can stack.
	var buff_id: String = "cons_%s_%d" % [item_id, int(Time.get_ticks_msec())]
	var data := {
		"consumable": true,
		"kind": kind,
		"hot_hp_per_sec": hp_per_sec,
		"hot_mp_per_sec": mp_per_sec,
		"hot_hp_left": hp_total,
		"hot_mp_left": mp_total,
		"hot_tick_acc": 0.0,
	}
	add_or_refresh_buff(buff_id, duration_sec, data)
	start_consumable_cooldown(kind, 5.0 if typ == "potion" else 10.0)
	return {"ok": true, "reason": "", "kind": kind}

# --- Components ---
@onready var c_stats: PlayerStats = $Components/Stats as PlayerStats
@onready var c_buffs: PlayerBuffs = $Components/Buffs as PlayerBuffs
@onready var c_combat: PlayerCombat = $Components/Combat as PlayerCombat
@onready var c_ability_caster: PlayerAbilityCaster = $Components/AbilityCaster as PlayerAbilityCaster
@onready var c_inv: PlayerInventoryComponent = $Components/Inventory as PlayerInventoryComponent
@onready var c_equip: PlayerEquipmentComponent = $Components/Equipment as PlayerEquipmentComponent
@onready var c_spellbook: PlayerSpellbook = $Components/Spellbook as PlayerSpellbook
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent
@onready var c_danger: DangerMeterComponent = $Components/Danger as DangerMeterComponent
@onready var cast_bar: ProgressBar = $CastBar
@onready var c_interaction: InteractionDetector = $InteractionDetector as InteractionDetector


func _ready() -> void:
	add_to_group("faction_units")
	# setup components
	# push primary tuning from Player root into Stats component
	c_stats.base_str = base_str
	c_stats.base_agi = base_agi
	c_stats.base_end = base_end
	c_stats.base_int = base_int
	c_stats.base_per = base_per
	c_stats.str_per_level = str_per_level
	c_stats.agi_per_level = agi_per_level
	c_stats.end_per_level = end_per_level
	c_stats.int_per_level = int_per_level
	c_stats.per_per_level = per_per_level

	c_stats.setup(self)
	c_buffs.setup(self)
	c_combat.setup(self)
	if c_ability_caster != null:
		c_ability_caster.setup(self)

	# inventory ref (чтобы LootUI/InventoryUI не ломались)
	c_inv.setup(self)
	inventory = c_inv.inventory
	c_equip.setup(self)
	if c_spellbook != null:
		c_spellbook.setup(self)
		if not c_spellbook.spellbook_changed.is_connected(_on_spellbook_changed):
			c_spellbook.spellbook_changed.connect(_on_spellbook_changed)

	# init stats
	c_stats.recalculate_for_level(true)

	if c_resource != null:
		c_resource.setup(self)
		c_resource.configure_from_class_id(class_id)
		if c_resource.resource_type == "mana":
			c_resource.sync_from_owner_fields_if_mana()
		else:
			c_resource.set_empty()

	_apply_spellbook_passives()
	if cast_bar != null:
		cast_bar.visible = false
		cast_bar.value = 0.0

func get_danger_meter() -> DangerMeterComponent:
	return c_danger


func _physics_process(_delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := Vector2.ZERO
	if mobile_move_dir != Vector2.ZERO:
		input_dir = mobile_move_dir
	else:
		input_dir = Vector2(
			Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
			Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
		)

	if c_ability_caster != null and c_ability_caster.is_casting() and input_dir.length() > 0.0:
		c_ability_caster.interrupt_cast("movement")
	if c_ability_caster != null and c_ability_caster.is_casting():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	velocity = input_dir * move_speed
	move_and_slide()


func _process(delta: float) -> void:
	if is_dead:
		return

	if c_buffs != null:
		c_buffs.tick(delta)
	if c_stats != null:
		c_stats.tick(delta)
	if c_ability_caster != null:
		c_ability_caster.tick(delta)
	if c_combat != null:
		c_combat.tick(delta)

	if cast_bar != null and c_ability_caster != null:
		var casting := c_ability_caster.is_casting()
		cast_bar.visible = casting
		cast_bar.value = c_ability_caster.get_cast_progress() * 100.0 if casting else 0.0


# -----------------------
# Compatibility API (как было раньше)
# -----------------------
func get_attack_damage() -> int:
	return c_combat.get_attack_damage()


func set_mobile_move_dir(dir: Vector2) -> void:
	mobile_move_dir = dir

func try_use_ability_slot(slot_index: int) -> void:
	if c_spellbook == null or c_ability_caster == null:
		return
	if slot_index < 0 or slot_index >= c_spellbook.loadout_slots.size():
		return
	var ability_id: String = c_spellbook.loadout_slots[slot_index]
	var target: Node = null
	var gm := _get_game_manager()
	if gm != null and gm.has_method("get_target"):
		target = gm.call("get_target")
	if target == null:
		target = self
	c_ability_caster.try_cast(ability_id, target)

func try_interact() -> void:
	if c_interaction != null:
		c_interaction.try_interact(self)

# Buffs API (BuffsUI/иконки)
func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	c_buffs.add_or_refresh_buff(id, duration_sec, data)

func remove_buff(id: String) -> void:
	c_buffs.remove_buff(id)

func get_buffs_snapshot() -> Array:
	return c_buffs.get_buffs_snapshot()


# CharacterHUD reads this if present
func get_stats_snapshot() -> Dictionary:
	if c_stats == null:
		return {}
	var snap: Dictionary = c_stats.get_stats_snapshot()
	# Add consumable HOT contribution (food/drink buffs) into regen numbers so CharacterHUD shows it.
	if c_buffs != null and c_buffs.has_method("get_consumable_hot_totals") and snap.has("derived"):
		var totals: Dictionary = c_buffs.call("get_consumable_hot_totals") as Dictionary
		var add_hp: float = float(totals.get("hp_per_sec", 0.0))
		var add_mp: float = float(totals.get("mp_per_sec", 0.0))
		if add_hp != 0.0 or add_mp != 0.0:
			var derived: Dictionary = snap.get("derived", {}) as Dictionary
			derived["hp_regen"] = float(derived.get("hp_regen", 0.0)) + add_hp
			derived["mana_regen"] = float(derived.get("mana_regen", 0.0)) + add_mp
			snap["derived"] = derived
			# Optional breakdown lines
			var breakdown: Dictionary = snap.get("derived_breakdown", {}) as Dictionary
			if add_hp != 0.0:
				var arr: Array = breakdown.get("hp_regen", [])
				arr.append({"source": "food/drink", "value": add_hp})
				breakdown["hp_regen"] = arr
			if add_mp != 0.0:
				var arr2: Array = breakdown.get("mana_regen", [])
				arr2.append({"source": "food/drink", "value": add_mp})
				breakdown["mana_regen"] = arr2
			snap["derived_breakdown"] = breakdown
	return snap


func _get_game_manager() -> Node:
	return NodeCache.get_game_manager(get_tree())


func _request_save(kind: String) -> void:
	var gm: Node = _get_game_manager()
	if gm != null and gm.has_method("request_save"):
		gm.call("request_save", kind)

func _on_spellbook_changed() -> void:
	_apply_spellbook_passives()
	if cast_bar != null:
		cast_bar.visible = false
		cast_bar.value = 0.0
	_request_save("spellbook_changed")

func _apply_spellbook_passives() -> void:
	if c_ability_caster == null or c_spellbook == null:
		return
	c_ability_caster.apply_active_aura(c_spellbook.aura_active)
	c_ability_caster.apply_active_stance(c_spellbook.stance_active)


func add_gold(amount: int) -> void:
	c_inv.add_gold(amount)
	_request_save("gold")


func add_item(item_id: String, amount: int) -> int:
	var remaining: int = c_inv.add_item(item_id, amount)
	_request_save("item")

	return remaining

func consume_item(item_id: String, amount: int = 1) -> int:
	var removed: int = c_inv.consume_item(item_id, amount)
	if removed > 0:
		_request_save("item")
	return removed


func add_xp(amount: int) -> void:
	c_stats.add_xp(amount)
	_request_save("xp")


func get_inventory_snapshot() -> Dictionary:
	return c_inv.get_inventory_snapshot()

func get_quick_slots() -> Array[String]:
	if c_inv == null:
		return []
	return c_inv.get_quick_slots()

func get_equipment_snapshot() -> Dictionary:
	if c_equip == null:
		return {}
	return c_equip.get_equipment_snapshot()


func apply_inventory_snapshot(snapshot: Dictionary) -> void:
	# UI / save helpers: apply inventory slots + equipped bags back to component.
	if c_inv != null:
		c_inv.apply_inventory_snapshot(snapshot)

func set_quick_slots(slots: Array) -> void:
	if c_inv == null:
		return
	c_inv.set_quick_slots(slots)
	_request_save("item")

func apply_equipment_snapshot(snapshot: Dictionary) -> void:
	if c_equip != null:
		c_equip.apply_equipment_snapshot(snapshot)

func try_equip_from_inventory_slot(inv_slot_index: int, target_slot_id: String) -> bool:
	if c_equip == null:
		return false
	return c_equip.try_equip_from_inventory_slot(inv_slot_index, target_slot_id)

func get_last_equip_fail_reason() -> String:
	if c_equip == null:
		return ""
	return c_equip.get_last_equip_fail_reason()

func get_preferred_equipment_slot(item_id: String) -> String:
	if c_equip == null:
		return ""
	return c_equip.get_preferred_slot_for_item(item_id)


func try_equip_bag_from_inventory_slot(inv_slot_index: int, bag_index: int) -> bool:
	return c_inv.try_equip_bag_from_inventory_slot(inv_slot_index, bag_index)

func try_unequip_bag_to_inventory(bag_index: int, preferred_slot_index: int = -1) -> bool:
	return c_inv.try_unequip_bag_to_inventory(bag_index, preferred_slot_index)

func try_move_or_swap_bag_slots(from_bag_index: int, to_bag_index: int) -> bool:
	return c_inv.try_move_or_swap_bag_slots(from_bag_index, to_bag_index)

# Damage API
func take_damage(raw_damage: int) -> void:
	c_stats.take_damage(raw_damage)

func take_damage_typed(raw_damage: int, dmg_type: String = "physical") -> void:
	c_stats.take_damage_typed(raw_damage, dmg_type)

func respawn_now() -> void:
	# телепорт на ближайший graveyard
	var gm: Node = _get_game_manager()
	if gm != null and gm.has_method("get_nearest_graveyard_position"):
		global_position = gm.call("get_nearest_graveyard_position", global_position)

	# восстановить HP/ману
	current_hp = max_hp
	if c_resource != null:
		if c_resource.resource_type == "mana":
			c_resource.set_full()
		else:
			c_resource.set_empty()

	# бафы не переносятся через смерть/респавн
	c_buffs.clear_all()

	is_dead = false


func apply_character_data(d: Dictionary) -> void:
	# имя/класс здесь не трогаем (они живут в сейве и UI), но статы/прогресс применяем
	level = int(d.get("level", level))
	xp = int(d.get("xp", xp))
	xp_to_next = int(d.get("xp_to_next", xp_to_next))
	class_id = String(d.get("class_id", d.get("class", class_id)))

	max_hp = int(d.get("max_hp", max_hp))
	current_hp = int(d.get("current_hp", current_hp))
	attack = int(d.get("attack", attack))
	defense = int(d.get("defense", defense))

	max_mana = int(d.get("max_mana", max_mana))
	mana = int(d.get("mana", mana))

	if c_resource != null:
		c_resource.configure_from_class_id(class_id)
		if c_resource.resource_type == "rage":
			var saved_value: int = int(d.get("resource", d.get("rage", c_resource.resource)))
			c_resource.max_resource = c_resource.rage_max_value
			c_resource.resource = clamp(saved_value, 0, c_resource.max_resource)
		else:
			c_resource.sync_from_owner_fields_if_mana()

	# Primary stats (new system, backward compatible)
	if c_stats != null:
		c_stats.apply_primary_data(d)
	faction_id = String(d.get("faction", faction_id))

	# inventory snapshot
	var inv_v: Variant = d.get("inventory", null)
	if inv_v is Dictionary:
		c_inv.apply_inventory_snapshot(inv_v as Dictionary)

	var equip_v: Variant = d.get("equipment", null)
	if equip_v is Dictionary:
		c_equip.apply_equipment_snapshot(equip_v as Dictionary)
	else:
		c_equip.apply_equipment_snapshot({})

	var buffs_v: Variant = d.get("buffs", [])
	if buffs_v is Array:
		c_buffs.apply_buffs_snapshot(buffs_v as Array)

	var spellbook_v: Variant = d.get("spellbook", null)
	if spellbook_v is Dictionary and c_spellbook != null:
		var sdata := spellbook_v as Dictionary
		c_spellbook.learned_ranks = sdata.get("learned_ranks", {}) as Dictionary
		c_spellbook.loadout_slots = _to_string_array(sdata.get("loadout_slots", ["", "", "", "", ""]))
		c_spellbook.aura_active = String(sdata.get("aura_active", ""))
		c_spellbook.stance_active = String(sdata.get("stance_active", ""))
		c_spellbook.buff_slots = _to_string_array(sdata.get("buff_slots", ["", "", ""]))
		c_spellbook._ensure_slots()
		_apply_spellbook_passives()
	if cast_bar != null:
		cast_bar.visible = false
		cast_bar.value = 0.0
	if c_spellbook != null and ((not (spellbook_v is Dictionary)) or c_spellbook.learned_ranks.is_empty()):
		_grant_starter_abilities()

	# Derived stats must be recalculated after primaries + buffs are in place
	if c_stats != null:
		c_stats.recalculate_for_level(false)

	# защита от “вошёл мёртвым”
	is_dead = false


func _grant_starter_abilities() -> void:
	if c_spellbook == null:
		return
	var class_def: Dictionary = PROG.get_class_data(class_id)
	var starters: Array = class_def.get("starter_abilities", []) as Array
	if starters.is_empty():
		return
	var db := get_node_or_null("/root/AbilityDB") as AbilityDatabase
	if db == null:
		return
	if not db.is_ready:
		if not _starter_grant_waiting_for_db and not db.initialized.is_connected(_on_ability_db_initialized_for_starters):
			_starter_grant_waiting_for_db = true
			db.initialized.connect(_on_ability_db_initialized_for_starters, CONNECT_ONE_SHOT)
		return
	_starter_grant_waiting_for_db = false
	var granted_any: bool = false
	for entry in starters:
		var ability_id := String(entry)
		if ability_id == "":
			continue
		var max_rank: int = int(max(1, db.get_max_rank(ability_id)))
		var before_rank := int(c_spellbook.learned_ranks.get(ability_id, 0))
		var after_rank := c_spellbook.learn_next_rank(ability_id, max_rank)
		if after_rank > before_rank:
			granted_any = true
	if granted_any:
		c_spellbook.emit_signal("spellbook_changed")
		_request_save("starter_abilities")

func _on_ability_db_initialized_for_starters() -> void:
	_starter_grant_waiting_for_db = false
	_grant_starter_abilities()


func export_character_data() -> Dictionary:
	# берём основу из AppState (там id/name/class и т.д.)
	var base: Dictionary = AppState.selected_character_data.duplicate(true)

	base["faction"] = faction_id
	base["class_id"] = class_id
	base["level"] = level
	base["xp"] = xp
	base["xp_to_next"] = xp_to_next

	base["max_hp"] = max_hp
	base["current_hp"] = current_hp
	base["attack"] = attack
	base["defense"] = defense

	base["max_mana"] = max_mana
	base["mana"] = mana

	if c_resource != null:
		if c_resource.resource_type == "mana":
			c_resource.sync_from_owner_fields_if_mana()
		base["resource_type"] = c_resource.resource_type
		base["max_resource"] = c_resource.max_resource
		base["resource"] = c_resource.resource
		if c_resource.resource_type == "rage":
			base["max_rage"] = c_resource.max_resource
			base["rage"] = c_resource.resource

	# Primary stats (saved)
	if c_stats != null:
		base.merge(c_stats.export_primary_data(), true)

	# inventory
	base["inventory"] = c_inv.get_inventory_snapshot()
	base["equipment"] = c_equip.get_equipment_snapshot()

	# position
	base["pos"] = {"x": float(global_position.x), "y": float(global_position.y)}	

	# buffs
	base["buffs"] = c_buffs.get_buffs_snapshot()
	if c_spellbook != null:
		base["spellbook"] = {
			"learned_ranks": c_spellbook.learned_ranks,
			"loadout_slots": c_spellbook.loadout_slots,
			"aura_active": c_spellbook.aura_active,
			"stance_active": c_spellbook.stance_active,
			"buff_slots": c_spellbook.buff_slots
		}

	return base


func get_faction_id() -> String:
	return faction_id

func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in value:
			out.append(String(entry))
	return out
