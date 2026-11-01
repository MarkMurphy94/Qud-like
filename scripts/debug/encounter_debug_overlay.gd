extends CanvasLayer

## F3 readout of the encounter simulation for wherever the player stands: the
## region's pools, the tile's cooldowns and snapshot.

@onready var text_label: Label = $Panel/Margin/Text


func _ready() -> void:
	TurnManager.turn_resolved.connect(_on_turn_resolved)


func _on_turn_resolved(_world_time: int) -> void:
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_encounter_debug"):
		visible = not visible
		if visible:
			refresh()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var game := get_tree().current_scene
	if game == null or not game.has_method("region_for_tile"):
		text_label.text = "No world loaded"
		return
	var player = game.player
	var tile: Vector2i = player.overworld_tile if player.in_local_area else player.get_current_tile()
	var tile_key := "%d,%d" % [tile.x, tile.y]
	var region: String = game.region_for_tile(tile)
	var now := WorldClock.total_hours()
	EncounterState.catch_up_region(region, WorldClock.day())

	var lines: PackedStringArray = []
	lines.append("Tile %s   %s (%s)" % [tile_key, region, EncounterState.region_biome(region)])
	lines.append("Day %d  %02d:%02d  %s, %s" % [WorldClock.day() + 1, WorldClock.hour(), WorldClock.minute(),
		WorldClock.time_of_day(), WorldClock.season()])
	lines.append("")
	var summary := EncounterState.region_summary(region)
	if summary.is_empty():
		lines.append("No populations live here")
	var pool_ids := summary.keys()
	pool_ids.sort()
	for pool_id: String in pool_ids:
		lines.append("%-10s %6.1f / %5.1f" % [pool_id, summary[pool_id]["count"], summary[pool_id]["capacity"]])

	var cooldowns := EncounterState.cooldowns_for(tile_key, now)
	if not cooldowns.is_empty():
		lines.append("")
		for entry_id: String in cooldowns:
			lines.append("cooldown %s: %.1fh" % [entry_id, cooldowns[entry_id] - now])
	var snapshot := EncounterState.snapshot_for(tile_key, now)
	if not snapshot.is_empty():
		lines.append("snapshot: %d survivors, %.1fh old" % [snapshot["survivors"].size(), now - float(snapshot["hour"])])
	text_label.text = "\n".join(lines)
