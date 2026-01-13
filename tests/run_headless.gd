extends SceneTree

const DATAB_DB_TIMEOUT_SEC := 8.0
const SAVE_TEST_PREFIX := "__smoke__"
const LOOT_PROFILE_PATH := "res://core/loot/profiles/loot_profile_aggressive_default.tres"

var _failures: Array[String] = []
var _datadb_initialized := false

func _init() -> void:
	randomize()
	call_deferred("_run")


func _run() -> void:
	await _test_datadb()
	await _test_save_system()
	await _test_loot_system()
	await _test_app_state()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE PASS")
		quit(0)
		return
	print("SMOKE FAIL (%d)" % _failures.size())
	for msg in _failures:
		printerr("- " + msg)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _pass(message: String) -> void:
	print(message)


func _test_datadb() -> void:
	var db := get_node_or_null("/root/DataDB")
	if db == null:
		_fail("DataDB autoload not found at /root/DataDB.")
		return

	var ready_property := _find_ready_property(db)
	if db.has_signal("initialized"):
		var ok := await _wait_for_datadb_ready(db, ready_property, DATAB_DB_TIMEOUT_SEC)
		if not ok:
			_fail("DataDB initialized signal timed out after %.1fs." % DATAB_DB_TIMEOUT_SEC)
			return
		_pass("DataDB initialized via signal/property.")
		return

	if ready_property != "":
		var ready_ok := await _wait_for_ready_property(db, ready_property, DATAB_DB_TIMEOUT_SEC)
		if not ready_ok:
			_fail("DataDB.%s did not become true after %.1fs." % [ready_property, DATAB_DB_TIMEOUT_SEC])
			return
		_pass("DataDB ready via %s." % ready_property)
		return

	_fail("DataDB has no ready signal/property (expected 'initialized' or 'is_ready/ready').")


func _test_save_system() -> void:
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system == null:
		_fail("SaveSystem autoload not found at /root/SaveSystem.")
		return

	var test_id := "%s_%d_%d" % [SAVE_TEST_PREFIX, int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]
	var payload := {
		"id": test_id,
		"name": "Smoke Test",
		"class": "adventurer",
		"level": 1
	}

	save_system.save_character_full(payload)
	var loaded: Dictionary = save_system.load_character_full(test_id)
	if loaded.is_empty():
		_fail("SaveSystem load returned empty data for %s." % test_id)
	else:
		_pass("SaveSystem save/load OK.")

	var deleted := save_system.delete_character(test_id)
	if not deleted:
		_fail("SaveSystem failed to delete test character %s." % test_id)
		return

	var post_delete := save_system.load_character_full(test_id)
	if not post_delete.is_empty():
		_fail("SaveSystem cleanup failed for %s." % test_id)
		return

	_pass("SaveSystem cleanup OK.")


func _test_loot_system() -> void:
	var loot_system := get_node_or_null("/root/LootSystem")
	if loot_system == null:
		_fail("LootSystem autoload not found at /root/LootSystem.")
		return

	var profile := ResourceLoader.load(LOOT_PROFILE_PATH)
	if not (profile is LootProfile):
		_fail("Loot profile at %s is not LootProfile." % LOOT_PROFILE_PATH)
		return

	var got_non_empty := false
	for _i in range(10):
		var loot: Dictionary = loot_system.generate_loot_from_profile(profile, 10)
		if not _loot_is_empty(loot):
			got_non_empty = true
			break

	if not got_non_empty:
		_fail("LootSystem returned empty loot for %s across multiple runs." % LOOT_PROFILE_PATH)
		return

	_pass("LootSystem generated loot from profile.")


func _test_app_state() -> void:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		_fail("AppState autoload not found at /root/AppState.")
		return

	if not app_state.has_method("set_state"):
		_fail("AppState has no set_state method for transitions.")
		return

	if app_state.current_state != AppState.FlowState.LOGIN:
		var boot_ok := app_state.set_state(AppState.FlowState.LOGIN)
		if not boot_ok:
			_fail("AppState failed to transition to LOGIN from %s." % app_state.current_state)
			return

	if not app_state.set_state(AppState.FlowState.CHARACTER_SELECT):
		_fail("AppState failed LOGIN -> CHARACTER_SELECT.")
		return

	if not app_state.set_state(AppState.FlowState.WORLD):
		_fail("AppState failed CHARACTER_SELECT -> WORLD.")
		return

	if not app_state.set_state(AppState.FlowState.CHARACTER_SELECT):
		_fail("AppState failed WORLD -> CHARACTER_SELECT.")
		return

	var illegal_ok := app_state.set_state(AppState.FlowState.BOOT)
	if illegal_ok:
		_fail("AppState allowed illegal CHARACTER_SELECT -> BOOT transition.")
		return

	_pass("AppState transitions OK (including illegal guard).")


func _find_ready_property(db: Object) -> String:
	var props: Array = db.get_property_list()
	for prop in props:
		var name := String(prop.get("name", ""))
		if name == "is_ready":
			return "is_ready"
	for prop in props:
		var name2 := String(prop.get("name", ""))
		if name2 == "ready":
			return "ready"
	return ""


func _wait_for_datadb_ready(db: Object, ready_property: String, timeout_sec: float) -> bool:
	if ready_property != "" and bool(db.get(ready_property)):
		return true

	_datadb_initialized = false
	var callable := Callable(self, "_on_datadb_initialized")
	if not db.is_connected("initialized", callable):
		db.connect("initialized", callable, CONNECT_ONE_SHOT)

	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _datadb_initialized:
			return true
		if ready_property != "" and bool(db.get(ready_property)):
			return true
		await process_frame
	return false


func _wait_for_ready_property(db: Object, ready_property: String, timeout_sec: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(db.get(ready_property)):
			return true
		await process_frame
	return false


func _on_datadb_initialized() -> void:
	_datadb_initialized = true


func _loot_is_empty(loot: Dictionary) -> bool:
	if loot.is_empty():
		return true
	var gold := int(loot.get("gold", 0))
	var slots: Array = loot.get("slots", [])
	return gold <= 0 and slots.is_empty()
