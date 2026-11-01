extends CanvasLayer

## F3 readout of the encounter simulation for wherever the player stands: the
## region's pools and live spawn modifiers, the tile's cooldowns and snapshot.
## The command line takes debug commands (type "help"). The player reads its
## keys by polling, so the tree is paused while the command line has focus.

const HELP := "spawn_mod <template> [target]  — target defaults to here\nspawn_mod_clear  — remove debug modifiers\npool <pool_id> <count>  — set a pool here\nmods  — list templates"

@onready var text_label: Label = $Panel/Margin/Rows/Text
@onready var result_label: Label = $Panel/Margin/Rows/Result
@onready var command: LineEdit = $Panel/Margin/Rows/Command

var _was_paused: bool = false


func _ready() -> void:
	TurnManager.turn_resolved.connect(_on_turn_resolved)
	command.text_submitted.connect(_on_command_submitted)
	command.focus_entered.connect(_on_command_focus_entered)
	command.focus_exited.connect(_on_command_focus_exited)
	result_label.visible = false


func _on_turn_resolved(_world_time: int) -> void:
	if visible:
		refresh()


func _input(event: InputEvent) -> void:
	if command.has_focus() and event.is_action_pressed("ui_cancel"):
		command.release_focus()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_encounter_debug"):
		visible = not visible
		if visible:
			refresh()
		else:
			command.release_focus()
		get_viewport().set_input_as_handled()


func _on_command_focus_entered() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true


func _on_command_focus_exited() -> void:
	get_tree().paused = _was_paused


func _on_command_submitted(text: String) -> void:
	command.clear()
	command.release_focus()
	var result := run_command(text)
	result_label.text = result
	result_label.visible = not result.is_empty()
	refresh()


## Where the player stands: {tile, tile_key, region}, or {} with no world.
func _here() -> Dictionary:
	var game := get_tree().current_scene
	if game == null or not game.has_method("region_for_tile"):
		return {}
	var player = game.player
	var tile: Vector2i = player.overworld_tile if player.in_local_area else player.get_current_tile()
	return {"tile": tile, "tile_key": "%d,%d" % [tile.x, tile.y], "region": game.region_for_tile(tile)}


func run_command(text: String) -> String:
	var parts := text.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var here := _here()
	match parts[0]:
		"help":
			return HELP
		"mods":
			return "templates: %s" % ", ".join(EncounterDatabase.modifier_templates.keys())
		"spawn_mod":
			if parts.size() < 2:
				return "usage: spawn_mod <template> [target]"
			var template: SpawnModifier = EncounterDatabase.get_modifier_template(parts[1])
			if template == null:
				return "unknown template '%s' — try: mods" % parts[1]
			var target := ""
			if parts.size() > 2:
				target = parts[2]
			elif not here.is_empty():
				target = here["tile_key"] if template.scope == "tile" else here["region"]
			var mod: SpawnModifier = EncounterState.add_modifier(parts[1], target, "debug")
			if mod == null:
				return "could not add %s" % parts[1]
			return "%s on %s for %.0f days (re-enter a tile to see it)" % [mod.id, mod.target if not mod.target.is_empty() else "the world", mod.duration_days]
		"spawn_mod_clear":
			EncounterState.remove_modifiers_from_event("debug")
			return "debug modifiers removed"
		"pool":
			if parts.size() < 3 or here.is_empty():
				return "usage: pool <pool_id> <count>"
			EncounterState.set_pool_count(here["region"], parts[1], float(parts[2]))
			return "%s in %s set to %s" % [parts[1], here["region"], parts[2]]
	return "unknown command '%s' — try: help" % parts[0]


func refresh() -> void:
	var here := _here()
	if here.is_empty():
		text_label.text = "No world loaded"
		return
	var tile_key: String = here["tile_key"]
	var region: String = here["region"]
	var now := WorldClock.total_hours()
	var today := WorldClock.total_days()
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

	var mods := EncounterState.live_modifiers_for(tile_key, region, today)
	if not mods.is_empty():
		lines.append("")
		for mod in mods:
			lines.append("mod %s: %.0f%%, %.1f days left" % [mod.id, mod.strength(today) * 100.0,
				mod.start_day + mod.duration_days - today])

	var cooldowns := EncounterState.cooldowns_for(tile_key, now)
	if not cooldowns.is_empty():
		lines.append("")
		for entry_id: String in cooldowns:
			lines.append("cooldown %s: %.1fh" % [entry_id, cooldowns[entry_id] - now])
	var snapshot := EncounterState.snapshot_for(tile_key, now)
	if not snapshot.is_empty():
		lines.append("snapshot: %d survivors, %.1fh old" % [snapshot["survivors"].size(), now - float(snapshot["hour"])])
	text_label.text = "\n".join(lines)
