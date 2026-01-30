extends Node
class_name DangerMeterComponent

const WINDOW_SEC := 3.0

var _events: Array[Dictionary] = []

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _prune(now_sec: float) -> void:
	var cutoff: float = now_sec - WINDOW_SEC
	while _events.size() > 0 and float(_events[0].get("t", 0.0)) < cutoff:
		_events.pop_front()

func on_damage_dealt(amount: float, _target: Node) -> void:
	if amount <= 0.0:
		return
	var now_sec := _now_sec()
	_events.append({"t": now_sec, "amount": amount})
	_prune(now_sec)

func get_dps(now_sec: float) -> float:
	_prune(now_sec)
	var sum_amount: float = 0.0
	for event in _events:
		sum_amount += float(event.get("amount", 0.0))
	return sum_amount / WINDOW_SEC

func reset() -> void:
	_events.clear()
