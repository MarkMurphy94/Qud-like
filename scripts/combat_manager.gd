extends Node
## CombatManager – turn-based combat orchestrator (autoload).
##
## Flow:
##   1. Hostile NPC detects player → calls CombatManager.trigger_combat(npc, player)
##   2. CombatManager pulls nearby allied hostiles into the fight
##   3. Initiative rolls (agility + d10) determine turn order
##   4. Each turn grants BASE_AP action points + BASE_MP movement points
##   5. Player acts manually; NPC turns are run automatically with small delays
##   6. Camera pans to the active combatant each turn
##   7. When all enemies are dead (or flee) combat ends

# ── Signals ──────────────────────────────────────────────────────────────────
signal combat_started
signal combat_ended
## Fired at the start of every turn. ap/mp are the fresh allowance for this turn.
signal turn_started(entity: Node2D, is_player: bool, ap: int, mp: int)
signal turn_ended(entity: Node2D)
## Fired whenever AP or MP changes mid-turn (so HUD can refresh).
signal resources_changed(ap: int, mp: int)
signal combatant_added(entity: Node2D)
## Fired for every notable combat event so the HUD log can display it.
## category: "move" | "attack" | "spell" | "death" | "info"
signal combat_event_logged(message: String, category: String)

# ── Constants ────────────────────────────────────────────────────────────────
const BASE_AP            := 3   # action points per turn
const BASE_MP            := 3   # movement points per turn
const AP_COST_ATTACK     := 2
const AP_COST_SPELL      := 2
const AP_COST_USE_ITEM   := 1
const AP_COST_EQUIP      := 1
const MP_COST_PER_TILE   := 1
const ALLY_PULL_RADIUS   := 8   # tiles – nearby hostiles auto-join
const NPC_TURN_MOVE_DELAY := 0.22  # seconds between each NPC step
const NPC_TURN_ATTACK_DELAY := 0.30

# ── State ─────────────────────────────────────────────────────────────────────
var in_combat     : bool   = false
## Array of slot-dictionaries; see _make_slot()
var combatants    : Array  = []
var current_index : int    = 0
var rng := RandomNumberGenerator.new()

var _player  : Node2D    = null
var _camera  : Camera2D  = null
var _hud     : Node      = null   # CombatHUD CanvasLayer instance
var _npc_turn_running : bool = false

# ── Ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	rng.randomize()
	name = "CombatManager"

# ── Public API ────────────────────────────────────────────────────────────────

## Called by any hostile NPC the moment it spots the player.
func trigger_combat(initiating_npc: Node2D, player: Node2D) -> void:
	if in_combat:
		_try_add_npc(initiating_npc)
		return

	_player  = player
	_camera  = _find_camera()
	in_combat = true
	combatants.clear()
	current_index = 0

	# Add player first so _add_slot skips duplicate later
	_add_slot(player, true)

	# Add triggering NPC and pull nearby allies
	_try_add_npc(initiating_npc)
	_pull_nearby_hostiles(initiating_npc)

	# Sort descending by initiative roll (highest acts first)
	combatants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.roll > b.roll
	)

	emit_signal("combat_started")
	_log("⚔ Combat begins!", "info")
	_show_hud()
	_start_turn()

## Called by the "End Turn" button in the HUD, or automatically when AP+MP are exhausted.
func end_current_turn() -> void:
	if not in_combat:
		return
	var slot := _current_slot()
	if slot.is_empty():
		return
	emit_signal("turn_ended", slot.entity)
	_advance_turn()

## Spend action points for the current player turn. Returns false if insufficient AP.
func spend_ap(amount: int = 1) -> bool:
	var slot := _current_player_slot()
	if slot.is_empty() or slot.ap < amount:
		return false
	slot.ap -= amount
	combatants[current_index] = slot
	emit_signal("resources_changed", slot.ap, slot.mp)
	if slot.ap <= 0 and slot.mp <= 0:
		end_current_turn()
	return true

## Spend movement points for the current player turn. Returns false if insufficient MP.
func spend_mp(amount: int = 1) -> bool:
	var slot := _current_player_slot()
	if slot.is_empty() or slot.mp < amount:
		return false
	slot.mp -= amount
	combatants[current_index] = slot
	emit_signal("resources_changed", slot.ap, slot.mp)
	if slot.ap <= 0 and slot.mp <= 0:
		end_current_turn()
	return true

func is_player_turn() -> bool:
	var slot := _current_slot()
	return not slot.is_empty() and slot.is_player

func get_current_ap() -> int:
	var slot := _current_player_slot()
	return slot.ap if not slot.is_empty() else 0

func get_current_mp() -> int:
	var slot := _current_player_slot()
	return slot.mp if not slot.is_empty() else 0

func get_combatant_names() -> Array:
	var names := []
	for i in combatants.size():
		var s: Dictionary = combatants[i]
		if not is_instance_valid(s.entity):
			continue
		var label: String = s.entity.get("npc_name") if s.entity.get("npc_name") else \
							("Player" if s.is_player else s.entity.name)
		names.append({"label": label, "is_player": s.is_player, "is_current": i == current_index})
	return names

# ── Internal helpers ──────────────────────────────────────────────────────────

func _make_slot(entity: Node2D, is_player: bool, roll: int) -> Dictionary:
	return {"entity": entity, "is_player": is_player, "roll": roll,
			"ap": BASE_AP, "mp": BASE_MP}

func _add_slot(entity: Node2D, is_player: bool) -> void:
	for s in combatants:
		if s.entity == entity:
			return   # already registered
	var init_val := _get_initiative(entity)
	var roll := init_val + rng.randi_range(1, 10)
	combatants.append(_make_slot(entity, is_player, roll))

func _try_add_npc(npc: Node2D) -> void:
	if not is_instance_valid(npc):
		return
	_add_slot(npc, false)
	if npc.has_method("enter_combat_mode"):
		npc.enter_combat_mode()
	emit_signal("combatant_added", npc)

func _pull_nearby_hostiles(origin: Node2D) -> void:
	var all_npcs: Array = origin.get_tree().get_nodes_in_group("NPCs")
	for npc in all_npcs:
		if npc == origin or not is_instance_valid(npc):
			continue
		var f: String = npc.get("faction") if npc.get("faction") != null else ""
		if not _is_hostile_faction(f):
			continue
		var dist: float = origin.global_position.distance_to(npc.global_position)
		if dist <= ALLY_PULL_RADIUS * 16:
			_try_add_npc(npc)

func _is_hostile_faction(f: String) -> bool:
	return f in ["OUTLAW", "BANDIT", "MONSTER", "GUARD_HOSTILE", "HOSTILE"]

func _current_slot() -> Dictionary:
	if combatants.is_empty() or current_index >= combatants.size():
		return {}
	return combatants[current_index]

func _current_player_slot() -> Dictionary:
	var s := _current_slot()
	return s if (not s.is_empty() and s.is_player) else {}

func _start_turn() -> void:
	_remove_dead_combatants()
	if _only_one_faction_left():
		end_combat()
		return
	if combatants.is_empty():
		end_combat()
		return
	if current_index >= combatants.size():
		current_index = 0

	var slot: Dictionary = combatants[current_index]
	slot.ap = BASE_AP
	slot.mp = BASE_MP
	combatants[current_index] = slot
	# Restore mana for caster NPCs
	if not slot.is_player and is_instance_valid(slot.entity) and slot.entity.has_method("restore_mana_for_turn"):
		slot.entity.restore_mana_for_turn()

	_pan_camera_to(slot.entity)
	_refresh_hud()
	var turn_name: String = "Player" if slot.is_player else \
		(slot.entity.get("npc_name") if slot.entity.get("npc_name") else slot.entity.name)
	_log("— %s's turn —" % turn_name, "info")
	emit_signal("turn_started", slot.entity, slot.is_player, slot.ap, slot.mp)

	if not slot.is_player and not _npc_turn_running:
		_npc_turn_running = true
		_run_npc_turn.call_deferred()

func _advance_turn() -> void:
	current_index = (current_index + 1) % max(1, combatants.size())
	_start_turn()

func _run_npc_turn() -> void:
	await get_tree().create_timer(0.35).timeout   # brief pause so player sees whose turn it is

	var slot: Dictionary = _current_slot()
	if slot.is_empty() or slot.is_player:
		_npc_turn_running = false
		return

	var npc: Node2D = slot.entity
	if not is_instance_valid(npc):
		_npc_turn_running = false
		end_current_turn()
		return

	var target: Node2D = _player
	if not is_instance_valid(target):
		_npc_turn_running = false
		end_current_turn()
		return

	# ── Move phase ─────────────────────────────────────────────────────────
	var attack_range: float = float(npc.get("combat_range")) if npc.get("combat_range") != null else 32.0
	var moves_taken := 0

	while slot.mp > 0 and moves_taken < BASE_MP:
		var dist: float = npc.global_position.distance_to(target.global_position)
		if dist <= attack_range:
			break   # already in melee range
		if npc.has_method("_combat_move_towards"):
			var moved: bool = npc._combat_move_towards(target.global_position)
			if moved:
				slot.mp -= 1
				moves_taken += 1
				combatants[current_index] = slot
				_pan_camera_to(npc)
				var npc_label: String = npc.get("npc_name") if npc.get("npc_name") else npc.name
				_log("%s moves closer." % npc_label, "move")
				await get_tree().create_timer(NPC_TURN_MOVE_DELAY).timeout
			else:
				break   # blocked
		else:
			break

	# ── Spell phase ────────────────────────────────────────────────────────
	var spell_cast := false
	if slot.ap >= AP_COST_SPELL and npc.has_method("get_best_combat_spell"):
		var dist_for_spell: float = npc.global_position.distance_to(target.global_position)
		var spell = npc.get_best_combat_spell(dist_for_spell)
		if spell != null:
			slot.ap -= AP_COST_SPELL
			combatants[current_index] = slot
			if npc.has_method("combat_cast_spell"):
				npc.combat_cast_spell(spell, target)
			var npc_label: String = npc.get("npc_name") if npc.get("npc_name") else npc.name
			_log("%s casts %s!" % [npc_label, spell.get_display_name()], "spell")
			await get_tree().create_timer(NPC_TURN_ATTACK_DELAY).timeout
			spell_cast = true

	# ── Attack phase ───────────────────────────────────────────────────────
	if not spell_cast:
		await get_tree().create_timer(0.15).timeout
		var dist_now: float = npc.global_position.distance_to(target.global_position)
		if dist_now <= attack_range and slot.ap >= AP_COST_ATTACK:
			slot.ap -= AP_COST_ATTACK
			combatants[current_index] = slot
			if npc.has_method("combat_attack"):
				npc.combat_attack(target)
			var npc_label: String = npc.get("npc_name") if npc.get("npc_name") else npc.name
			_log("%s attacks the player!" % npc_label, "attack")
			await get_tree().create_timer(NPC_TURN_ATTACK_DELAY).timeout

	_npc_turn_running = false
	end_current_turn()

func _remove_dead_combatants() -> void:
	combatants = combatants.filter(func(s: Dictionary) -> bool:
		if not is_instance_valid(s.entity):
			return false
		if s.is_player:
			return true
		# NPCState.DEAD == 10
		var st = s.entity.get("state")
		return st == null or int(st) != 10
	)
	# Re-clamp index after removal
	if combatants.size() > 0:
		current_index = current_index % combatants.size()

func _only_one_faction_left() -> bool:
	var has_player := false
	var has_enemy  := false
	for s in combatants:
		if not is_instance_valid(s.entity):
			continue
		if s.is_player:
			has_player = true
		else:
			has_enemy = true
	return not (has_player and has_enemy)

func end_combat() -> void:
	in_combat = false
	_npc_turn_running = false
	var enemies := combatants.filter(func(s: Dictionary) -> bool: return not s.is_player)
	combatants.clear()
	current_index = 0

	# Return camera to player
	if _camera and is_instance_valid(_camera):
		var tw := create_tween()
		tw.tween_property(_camera, "offset", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_SINE)

	_hide_hud()
	_log("⚔ Combat ended.", "info")
	emit_signal("combat_ended")

	# Tell all NPCs to drop out of combat mode
	for s in enemies:
		if is_instance_valid(s.entity) and s.entity.has_method("exit_combat_mode"):
			s.entity.exit_combat_mode()

# ── Initiative ────────────────────────────────────────────────────────────────
func _get_initiative(entity: Node2D) -> int:
	var st = entity.get("stats")
	if st != null:
		return int(st.get("agility", 10))
	return 10

# ── Camera ────────────────────────────────────────────────────────────────────
func _find_camera() -> Camera2D:
	if is_instance_valid(_player):
		return _player.get_node_or_null("Camera2D")
	return null

func _pan_camera_to(target: Node2D) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(target):
		return
	if not is_instance_valid(_player):
		return
	var desired_offset := target.global_position - _player.global_position
	var tw := create_tween()
	tw.tween_property(_camera, "offset", desired_offset, 0.35).set_trans(Tween.TRANS_SINE)

# ── Event log ─────────────────────────────────────────────────────────────────
func _log(message: String, category: String = "info") -> void:
	emit_signal("combat_event_logged", message, category)

# ── HUD ───────────────────────────────────────────────────────────────────────
func _show_hud() -> void:
	if _hud == null:
		var hud_script = load("res://scripts/combat_hud.gd")
		_hud = CanvasLayer.new()
		_hud.layer = 12
		_hud.set_script(hud_script)
		get_tree().get_root().add_child(_hud)
	_hud.visible = true
	_refresh_hud()

func _hide_hud() -> void:
	if _hud:
		_hud.visible = false

func _refresh_hud() -> void:
	if _hud and _hud.visible and _hud.has_method("refresh"):
		var slot := _current_slot()
		var ap = slot.ap if not slot.is_empty() else 0
		var mp = slot.mp if not slot.is_empty() else 0
		_hud.refresh(get_combatant_names(), ap, mp, is_player_turn())
