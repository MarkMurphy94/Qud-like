extends Node
## TurnManager — the global turn scheduler (autoload).
##
## There is no separate "combat mode". The world is always turn-based:
## nothing in it moves until the player does something. When the player
## commits to an action, world time advances by that action's cost and every
## nearby actor spends the energy it just accrued.
##
## ENERGY MODEL
##   • A "standard" action costs TICKS_PER_ACTION ticks of world time.
##   • Every actor has a `speed` (NORMAL_SPEED = one action per standard turn)
##     and an `energy` pool.
##   • Advancing world time by N ticks grants each actor `N * speed / 100`
##     energy; it then acts repeatedly while it can afford TICKS_PER_ACTION.
##   So speed 50 acts every other player turn, speed 200 acts twice per turn,
##   and the player's own speed shrinks the tick cost of their actions.
##
## ACTOR CONTRACT
##   An actor is any node in the "NPCs" group exposing:
##     var energy: int
##     var speed: int
##     func take_turn() -> int   # returns the tick cost of what it did
##
## VISUALS
##   Actions resolve instantly in game-logic terms — bodies teleport a whole
##   tile — and the *sprites* tween to catch up over STEP_DURATION. That single
##   constant is also what paces the player's input, so everything on screen
##   slides in lockstep.

# ── Tuning ───────────────────────────────────────────────────────────────────
## Tick cost of one standard action for an actor of NORMAL_SPEED.
const TICKS_PER_ACTION := 1000
## Speed at which an actor takes exactly one standard action per turn.
const NORMAL_SPEED := 100
## Seconds a one-tile slide takes, and therefore the fastest the player can
## chain actions by holding a movement key.
const STEP_DURATION := 0.12
## Actors further than this from the player are frozen — a fully populated
## settlement should not pay for peasants the player cannot see.
const ACTIVE_RADIUS_TILES := 40
## Safety valve so a very fast (or misbehaving) actor cannot lock up the frame.
const MAX_ACTIONS_PER_RESOLVE := 4
## Standard turns per in-game hour, used by NPC schedules.
const TURNS_PER_GAME_HOUR := 60

# ── Signals ──────────────────────────────────────────────────────────────────
## Fired once per player action, after every actor has finished resolving.
signal turn_resolved(world_time: int)
## Fired for every notable event so the message log can display it.
## category: "move" | "attack" | "spell" | "death" | "info"
signal message_logged(text: String, category: String)

# ── State ────────────────────────────────────────────────────────────────────
## Monotonic world clock in ticks. Owned here; NPC schedules read it.
var world_time: int = 0
## True while a player action is being resolved. Everything that asks "may I
## act?" checks this — it is the replacement for the old `in_combat` flag.
var resolving: bool = false

var _player: Node2D = null


func _ready() -> void:
	name = "TurnManager"


# ═══════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════

## Resolve one player action. `base_cost` is the cost before the player's own
## speed is applied — pass a multiple of TICKS_PER_ACTION for slower actions.
func take_player_action(base_cost: int = TICKS_PER_ACTION) -> void:
	if resolving:
		return
	resolving = true

	var cost := scale_cost(base_cost, _actor_speed(get_player()))
	world_time += cost
	_run_actors(cost)
	turn_resolved.emit(world_time)

	# Let the sprite tweens play out before the next action is accepted, so a
	# held movement key produces a steady walk rather than a teleport.
	await get_tree().create_timer(STEP_DURATION).timeout
	resolving = false


## Stand still for one turn.
func wait() -> void:
	take_player_action()


## Tick cost of an action for an actor of the given speed.
func scale_cost(base_cost: int, speed: int) -> int:
	return maxi(1, roundi(float(base_cost) * float(NORMAL_SPEED) / float(maxi(1, speed))))


## Whole standard turns elapsed since the world began.
func turns_elapsed() -> int:
	return world_time / TICKS_PER_ACTION


## In-game hour (0–23) derived from the world clock. NPC schedules use this.
func get_hour() -> int:
	return int(turns_elapsed() / TURNS_PER_GAME_HOUR) % 24


func get_player() -> Node2D:
	if not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("Player")
		_player = players[0] if not players.is_empty() else null
	return _player


## The actor standing on `tile`, or null. Used for bump-to-attack, so the
## player never has to guess whether a body is in the way.
func actor_at(tile: Vector2i) -> Node2D:
	var player := get_player()
	if player == null:
		return null
	for actor in get_tree().get_nodes_in_group("NPCs"):
		if not is_instance_valid(actor):
			continue
		if actor.has_method("is_alive") and not actor.is_alive():
			continue
		if player.world_to_tile(actor.global_position) == tile:
			return actor
	return null


func log_message(text: String, category: String = "info") -> void:
	message_logged.emit(text, category)


# ═══════════════════════════════════════════════════════════════════════
#  INTERNAL
# ═══════════════════════════════════════════════════════════════════════

## Grant `ticks` worth of energy to every active actor and let each one spend it.
func _run_actors(ticks: int) -> void:
	var player := get_player()
	var origin: Vector2 = player.global_position if player else Vector2.ZERO
	var radius_px := float(ACTIVE_RADIUS_TILES * MainGameState.TILE_SIZE)

	for actor in get_tree().get_nodes_in_group("NPCs"):
		if not is_instance_valid(actor) or not actor.has_method("take_turn"):
			continue
		if actor.global_position.distance_to(origin) > radius_px:
			continue

		actor.energy += roundi(float(ticks) * float(_actor_speed(actor)) / float(NORMAL_SPEED))

		var actions := 0
		while actor.energy >= TICKS_PER_ACTION and actions < MAX_ACTIONS_PER_RESOLVE:
			actions += 1
			# A zero-cost action would spin forever; charge at least one tick.
			actor.energy -= maxi(1, int(actor.take_turn()))
			if not is_instance_valid(actor):
				break

		# Never bank more than one action's worth, so an actor that was blocked
		# or capped does not burst on the next turn.
		if is_instance_valid(actor):
			actor.energy = mini(actor.energy, TICKS_PER_ACTION - 1)


func _actor_speed(actor: Object) -> int:
	if actor == null:
		return NORMAL_SPEED
	var value = actor.get("speed")
	return int(value) if value != null else NORMAL_SPEED
