extends Node
class_name ResourceComponent

const PROG := preload("res://core/stats/progression.gd")

var owner_entity: Node = null
var resource_type: String = "mana"
var max_resource: int = 1
var resource: int = 1
var label_name: String = "Mana"

@export var rage_max_value: int = 100
@export var rage_gain_on_deal_flat: int = 2
@export var rage_gain_on_take_flat: int = 3
@export var rage_decay_delay_sec: float = 0.0
@export var rage_decay_per_sec: float = 2.0

var _last_combat_time_sec: float = -999999.0
var _rage_decay_accum: float = 0.0

func setup(owner: Node) -> void:
	owner_entity = owner
	set_process(true)

func set_type(t: String) -> void:
	resource_type = t
	label_name = "Rage" if t == "rage" else "Mana"

func configure_from_class_id(class_id: String) -> void:
	var t: String = "mana"
	if PROG != null:
		t = String(PROG.get_resource_type_for_class(class_id))
	set_type(t)

	if resource_type == "rage":
		max_resource = rage_max_value
		resource = clamp(resource, 0, max_resource)
		return

	sync_from_owner_fields_if_mana()
	max_resource = max(0, int(max_resource))
	if max_resource <= 0:
		resource = 0
	else:
		resource = clamp(int(resource), 0, max_resource)

func sync_from_owner_fields_if_mana() -> void:
	if resource_type != "mana":
		return
	if owner_entity == null:
		return
	if owner_entity.get("max_mana") != null and owner_entity.get("mana") != null:
		max_resource = max(0, int(owner_entity.get("max_mana")))
		if max_resource <= 0:
			resource = 0
		else:
			resource = clamp(int(owner_entity.get("mana")), 0, max_resource)
		return

	if owner_entity.has_node("Components/Stats"):
		var stats: Node = owner_entity.get_node("Components/Stats")
		if stats != null and stats.has_method("get_stats_snapshot"):
			var snap: Dictionary = stats.call("get_stats_snapshot") as Dictionary
			var derived: Dictionary = snap.get("derived", {}) as Dictionary
			var mx: int = int(derived.get("max_mana", 0))
			max_resource = max(0, mx)
			if max_resource <= 0:
				resource = 0
			elif resource <= 1 or resource > max_resource:
				resource = max_resource
			else:
				resource = clamp(resource, 0, max_resource)

func sync_to_owner_fields_if_mana() -> void:
	if resource_type != "mana":
		return
	if owner_entity == null:
		return
	if owner_entity.get("max_mana") == null or owner_entity.get("mana") == null:
		return
	owner_entity.set("max_mana", max_resource)
	owner_entity.set("mana", resource)

func mark_in_combat() -> void:
	_last_combat_time_sec = float(Time.get_ticks_msec()) / 1000.0

func on_damage_dealt() -> void:
	mark_in_combat()
	if resource_type == "rage":
		add(rage_gain_on_deal_flat)

func on_damage_taken() -> void:
	mark_in_combat()
	if resource_type == "rage":
		add(rage_gain_on_take_flat)

func add(delta: int) -> void:
	resource = clamp(resource + delta, 0, max_resource)
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func set_full() -> void:
	resource = max_resource
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func set_empty() -> void:
	resource = 0
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func get_text() -> String:
	return "%s %d/%d" % [label_name, resource, max_resource]

func _process(delta: float) -> void:
	if resource_type != "rage":
		return
	if resource <= 0:
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	if (now_sec - _last_combat_time_sec) < rage_decay_delay_sec:
		return
	_rage_decay_accum += rage_decay_per_sec * delta
	var decay_amount: int = int(floor(_rage_decay_accum))
	if decay_amount <= 0:
		return
	resource = max(0, resource - decay_amount)
	_rage_decay_accum -= float(decay_amount)
