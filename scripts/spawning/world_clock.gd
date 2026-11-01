extends Node

## Calendar view over TurnManager.world_time (autoload WorldClock). TurnManager
## owns the one clock; this only names its hours, days and seasons and
## announces when they roll over. Restoring world_time from a save must be
## followed by sync(), or the jump is announced as hundreds of elapsed days.

const DAYS_PER_SEASON := 28
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]

signal hour_changed(hour: int)
signal day_changed(day: int)

var _last_hour_index: int = 0
var _last_day: int = 0


func _ready() -> void:
	TurnManager.turn_resolved.connect(_on_turn_resolved)
	sync()


func sync() -> void:
	_last_hour_index = int(total_hours())
	_last_day = day()


func total_hours() -> float:
	return float(TurnManager.world_time) / float(TurnManager.TICKS_PER_ACTION * TurnManager.TURNS_PER_GAME_HOUR)


func total_days() -> float:
	return total_hours() / 24.0


func day() -> int:
	return int(total_hours()) / 24


func hour() -> int:
	return int(total_hours()) % 24


func time_of_day() -> String:
	var h := hour()
	if h >= 5 and h < 7:
		return "dawn"
	if h >= 7 and h < 18:
		return "day"
	if h >= 18 and h < 20:
		return "dusk"
	return "night"


func season() -> String:
	return SEASONS[(day() / DAYS_PER_SEASON) % SEASONS.size()]


func _on_turn_resolved(_world_time: int) -> void:
	var hour_index := int(total_hours())
	if hour_index != _last_hour_index:
		_last_hour_index = hour_index
		hour_changed.emit(hour())
	# One emission per day crossed, so a long rest still runs every daily step.
	var today := day()
	while _last_day < today:
		_last_day += 1
		day_changed.emit(_last_day)
